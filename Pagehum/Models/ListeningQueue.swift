// Modified for Pagehum: unified application and command-line naming.
import Foundation
import Combine
import SwiftData

/// A session queue owned by the playback model, independent of view navigation.
/// Entries are snapshots so deleting a library object cannot invalidate queue UI.
@MainActor
final class ListeningQueue: ObservableObject {
    struct Entry: Identifiable {
        let id: PersistentIdentifier
        let title: String
        let remainingCharacters: Int
        let textID: String

        init(_ item: PlaylistItem) {
            id = item.persistentModelID
            title = item.title
            remainingCharacters = ListeningQueue.remainingCharacters(in: item)
            textID = OfflineAudioRequest.textIdentifier(item.fullText)
        }
    }

    @Published private(set) var current: Entry?
    @Published private(set) var upcoming: [Entry] = []
    @Published private(set) var failure: String?
    private weak var model: ReaderModel?
    private var advanceTask: Task<Void, Never>?
    private var revision = 0
    private var pauseAfterAdvance = false

    init(model: ReaderModel) { self.model = model }

    var isActive: Bool { current != nil }

    func contains(_ id: PersistentIdentifier) -> Bool {
        current?.id == id || upcoming.contains { $0.id == id }
    }

    func isManaging(_ id: PersistentIdentifier?) -> Bool {
        current != nil && current?.id == id
    }

    /// Preserve an existing playing/paused article when adding the first batch.
    /// Otherwise begin the batch immediately, in the order supplied by Library.
    func enqueue(_ items: [PlaylistItem]) {
        guard let model, !items.isEmpty, !model.isLoading else { return }
        if current == nil, model.progress < 1,
           model.isPlaying || model.isPaused || model.isPreparing,
           let id = model.currentPlaylistItemID, let item = find(id) {
            current = Entry(item)
        }
        for item in items where !item.isDeleted && !contains(item.persistentModelID) {
            upcoming.append(Entry(item))
        }
        if current == nil { advance() }
    }

    func remove(_ id: PersistentIdentifier) {
        upcoming.removeAll { $0.id == id }
    }

    func move(_ id: PersistentIdentifier, by offset: Int) {
        guard let index = upcoming.firstIndex(where: { $0.id == id }),
              upcoming.indices.contains(index + offset) else { return }
        upcoming.swapAt(index, index + offset)
    }

    /// List-style reordering; `destination` is an index in the list before the move.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.compactMap { upcoming.indices.contains($0) ? upcoming[$0] : nil }
        var remaining = upcoming.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = min(remaining.count, max(0, destination - source.filter { $0 < destination }.count))
        remaining.insert(contentsOf: moving, at: insertAt)
        upcoming = remaining
    }

    func remove(atOffsets offsets: IndexSet) {
        upcoming = upcoming.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
    }

    func clearUpcoming() { upcoming = [] }

    /// End queue ownership without interrupting the currently audible article.
    func end() {
        revision += 1
        advanceTask?.cancel()
        advanceTask = nil
        pauseAfterAdvance = false
        current = nil
        upcoming = []
        failure = nil
    }

    func pausePendingAdvance() {
        if advanceTask != nil { pauseAfterAdvance = true }
    }

    func skip() {
        guard current != nil, let model else { return }
        revision += 1
        advanceTask?.cancel()
        advanceTask = nil
        if isManaging(model.currentPlaylistItemID) {
            model.saveProgressNow()
            let index = model.currentSentenceIndex
            model.stop()
            // Keep the skipped article resumable, including when it was last.
            if !model.sentences.isEmpty { model.seekToSentence(index) }
        }
        advance()
    }

    func retry() {
        guard let current else { return }
        activate(current)
    }

    /// Called after the old article's progress has been saved. Yield before
    /// replacing the scheduler's content to avoid reentering its completion stack.
    func articleFinished() {
        guard let model, isManaging(model.currentPlaylistItemID), failure == nil else { return }
        let expectedRevision = revision
        let expectedID = current?.id
        advanceTask?.cancel()
        advanceTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled, self.revision == expectedRevision,
                  self.current?.id == expectedID, self.failure == nil else { return }
            self.advanceTask = nil
            let autoplay = !self.pauseAfterAdvance
            self.pauseAfterAdvance = false
            self.advance(autoplay: autoplay)
        }
    }

    /// Queue playback fails visibly instead of silently skipping spoken content.
    func playbackFailed(_ message: String, at index: Int) {
        guard let model, isManaging(model.currentPlaylistItemID) else { return }
        revision += 1
        advanceTask?.cancel()
        advanceTask = nil
        model.stop()
        if !model.sentences.isEmpty { model.seekToSentence(index) }
        failure = message
        model.errorMessage = message
    }

    private func advance(autoplay: Bool = true) {
        failure = nil
        guard !upcoming.isEmpty else { end(); return }
        let entry = upcoming.removeFirst()
        current = entry
        activate(entry, autoplay: autoplay)
    }

    private func activate(_ entry: Entry, autoplay: Bool = true) {
        guard let model else { return }
        failure = nil
        guard let item = find(entry.id) else {
            failure = "This article is no longer in your library. Skip it to continue."
            return
        }
        guard model.openLibraryItem(item, preservingQueue: true, forceReload: true) else {
            failure = model.errorMessage ?? "This article has no readable text."
            return
        }
        guard autoplay else { return }
        guard model.canPlayCurrentContent else {
            failure = "The voice engine isn’t ready yet. Retry when it has finished loading."
            return
        }
        model.play()
    }

    private func find(_ id: PersistentIdentifier) -> PlaylistItem? {
        // Fetch rather than model(for:), which can return a fault for a deleted ID.
        guard let context = model?.modelContext,
              let items = try? context.fetch(FetchDescriptor<PlaylistItem>()) else { return nil }
        return items.first { $0.persistentModelID == id && !$0.isDeleted }
    }

    static func remainingCharacters(in item: PlaylistItem) -> Int {
        let segmented = ArticleSegmenter.segment(item.fullText, splitProse: ReaderModel.splitIntoSentences)
        let completed = item.progressPercent >= 1 || item.status == PlaylistItem.Status.completed.rawValue
        let index: Int
        if completed { index = 0 }
        else if let offset = item.playbackTextOffset {
            index = segmented.sentenceStartOffsetsUTF16.lastIndex(where: { $0 <= offset }) ?? 0
        } else { index = max(0, item.lastSentenceIndex) }
        return segmented.sentences.dropFirst(min(index, segmented.sentences.count)).reduce(0) { $0 + $1.count }
    }

    static func durationLabel(characters: Int, speed: Float) -> String {
        let seconds = Double(characters) / 13 / Double(max(speed, 0.1))
        if seconds < 60 { return "Under 1 min (est.)" }
        let minutes = Int(ceil(seconds / 60))
        if minutes < 60 { return "About \(minutes) min" }
        return minutes % 60 == 0 ? "About \(minutes / 60) hr" : "About \(minutes / 60) hr \(minutes % 60) min"
    }
}
