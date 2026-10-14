// Modified for Pagehum: unified application and command-line naming.
import AVFoundation
import SwiftData
import Testing
@testable import Pagehum

@MainActor
struct ListeningQueueTests {
    @Test
    func resumesSavedPositionAdvancesInOrderAndRestartsCompletedItems() async throws {
        let fixture = try QueueFixture()
        defer { fixture.cleanup() }
        let first = try fixture.add("First", text: "Opening sentence. Remaining sentence.")
        first.lastSentenceIndex = 1
        first.playbackTextOffset = "Opening sentence. ".utf16.count
        first.progressPercent = 0.5
        let second = try fixture.add("Second")
        second.status = "completed"
        second.progressPercent = 1
        second.playbackTextOffset = second.fullText.utf16.count
        let third = try fixture.add("Third")

        fixture.queue.enqueue([first, second, third, first])
        try await fixture.wait { fixture.model.isPlaying }
        #expect(fixture.model.currentSentenceIndex == 1)
        #expect(fixture.queue.upcoming.map(\.id) == [second.persistentModelID, third.persistentModelID])

        try await fixture.finishCurrent()
        try await fixture.wait { fixture.model.currentPlaylistItemID == second.persistentModelID && fixture.model.isPlaying }
        #expect(first.progressPercent == 1)
        #expect(first.status == "completed")
        #expect(fixture.model.currentSentenceIndex == 0)
        #expect(second.status == "inProgress")

        try await fixture.finishCurrent()
        try await fixture.wait { fixture.model.currentPlaylistItemID == third.persistentModelID && fixture.model.isPlaying }
        try await fixture.finishCurrent()
        try await fixture.wait { !fixture.queue.isActive }
        #expect(third.progressPercent == 1)
        #expect(!fixture.model.isPlaying)
    }

    @Test
    func appendingPreservesPausedPlaybackAndQueueEditsKeepLibraryItems() async throws {
        let fixture = try QueueFixture()
        defer { fixture.cleanup() }
        let first = try fixture.add("First")
        let second = try fixture.add("Second")
        let third = try fixture.add("Third")
        fixture.model.openLibraryItem(first)
        fixture.model.play()
        try await fixture.wait { fixture.model.isPlaying }
        fixture.model.pause()

        fixture.queue.enqueue([first, second, third, second])
        #expect(fixture.model.isPaused)
        #expect(!fixture.model.isPlaying)
        #expect(fixture.model.currentPlaylistItemID == first.persistentModelID)
        #expect(fixture.queue.upcoming.count == 2)
        fixture.queue.move(third.persistentModelID, by: -1)
        #expect(fixture.queue.upcoming.map(\.id) == [third.persistentModelID, second.persistentModelID])
        fixture.queue.remove(second.persistentModelID)
        #expect(try fixture.context.fetchCount(FetchDescriptor<PlaylistItem>()) == 3)

        fixture.model.play()
        try await fixture.finishCurrent()
        try await fixture.wait { fixture.model.currentPlaylistItemID == third.persistentModelID }
    }

    @Test
    func listEditingMovesAndRemovesUpcomingByOffsets() async throws {
        let fixture = try QueueFixture()
        defer { fixture.cleanup() }
        let items = try ["First", "Second", "Third", "Fourth"].map { try fixture.add($0) }
        fixture.queue.enqueue(items)
        try await fixture.wait { fixture.model.isPlaying }
        fixture.queue.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(fixture.queue.upcoming.map(\.title) == ["Fourth", "Second", "Third"])
        fixture.queue.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(fixture.queue.upcoming.map(\.title) == ["Second", "Third", "Fourth"])
        fixture.queue.remove(atOffsets: IndexSet(integer: 1))
        #expect(fixture.queue.upcoming.map(\.title) == ["Second", "Fourth"])
        #expect(try fixture.context.fetchCount(FetchDescriptor<PlaylistItem>()) == 4)
    }

    @Test
    func generationFailurePausesQueueAndRetryContinuesFromSavedPosition() async throws {
        var shouldFail = true
        let fixture = try QueueFixture { text in !(shouldFail && text.contains("Broken")) }
        defer { fixture.cleanup() }
        let first = try fixture.add("Broken", text: "Broken sentence. Another sentence. A third sentence. A fourth sentence.")
        let second = try fixture.add("Healthy")
        fixture.queue.enqueue([first, second])
        try await fixture.wait { fixture.queue.failure != nil }
        #expect(!fixture.model.isPlaying)
        #expect(!fixture.model.isPreparing)
        #expect(first.progressPercent < 1)
        #expect(fixture.queue.current?.id == first.persistentModelID)
        #expect(fixture.queue.upcoming.first?.id == second.persistentModelID)

        shouldFail = false
        fixture.queue.retry()
        try await fixture.wait { fixture.model.isPlaying }
        #expect(fixture.queue.failure == nil)
        try await fixture.finishCurrent()
        try await fixture.wait { fixture.model.currentPlaylistItemID == second.persistentModelID && fixture.model.isPlaying }
    }

    @Test
    func emptyAndDeletedArticlesOfferSkipWithoutLosingQueue() async throws {
        let fixture = try QueueFixture()
        defer { fixture.cleanup() }
        let empty = try fixture.add("Empty", text: "   ")
        let deleted = try fixture.add("Deleted")
        let healthy = try fixture.add("Healthy")
        fixture.queue.enqueue([empty, deleted, healthy])
        #expect(fixture.queue.failure != nil)
        #expect(fixture.queue.upcoming.count == 2)
        fixture.context.delete(deleted)
        try fixture.context.save()
        fixture.queue.skip()
        #expect(fixture.queue.failure != nil)
        #expect(fixture.queue.current?.title == "Deleted")
        fixture.queue.skip()
        try await fixture.wait { fixture.model.isPlaying }
        #expect(fixture.model.currentPlaylistItemID == healthy.persistentModelID)
        fixture.queue.skip()
        #expect(!fixture.queue.isActive)
        #expect(!fixture.model.isPlaying)
        #expect(healthy.progressPercent < 1)
    }

    @Test
    func openingDifferentContentCancelsPendingAutomaticAdvance() async throws {
        let fixture = try QueueFixture()
        defer { fixture.cleanup() }
        let first = try fixture.add("First")
        let second = try fixture.add("Second")
        let manual = try fixture.add("Manual")
        fixture.queue.enqueue([first, second])
        try await fixture.wait { fixture.model.isPlaying }
        fixture.completeScheduledArticle()
        #expect(fixture.model.progress == 1)
        fixture.model.openLibraryItem(manual)
        try await Task.sleep(for: .milliseconds(30))
        #expect(!fixture.queue.isActive)
        #expect(fixture.model.currentPlaylistItemID == manual.persistentModelID)
        #expect(!fixture.model.isPlaying)
        #expect(first.progressPercent == 1)
    }

    @Test
    func pauseAtArticleBoundaryPreventsNextArticleAutoplay() async throws {
        let fixture = try QueueFixture()
        defer { fixture.cleanup() }
        let first = try fixture.add("First")
        let second = try fixture.add("Second")
        fixture.queue.enqueue([first, second])
        try await fixture.wait { fixture.model.isPlaying }
        fixture.completeScheduledArticle()
        fixture.model.pause()
        try await fixture.wait { fixture.model.currentPlaylistItemID == second.persistentModelID }
        #expect(!fixture.model.isPlaying)
        #expect(!fixture.model.isPreparing)
        #expect(fixture.queue.current?.id == second.persistentModelID)
        fixture.model.play()
        try await fixture.wait { fixture.model.isPlaying }
    }

    @Test
    func durationUsesSavedOffsetsAndPlaybackSpeed() throws {
        let fixture = try QueueFixture()
        defer { fixture.cleanup() }
        let item = try fixture.add("Duration", text: "First sentence. Remaining sentence.")
        item.playbackTextOffset = "First sentence. ".utf16.count
        #expect(ListeningQueue.remainingCharacters(in: item) == "Remaining sentence.".count)
        item.status = "completed"
        #expect(ListeningQueue.remainingCharacters(in: item) > "Remaining sentence.".count)
        #expect(ListeningQueue.durationLabel(characters: 4680, speed: 1) == "About 6 min")
        #expect(ListeningQueue.durationLabel(characters: 4680, speed: 2) == "About 3 min")
    }
}

@MainActor
private final class QueueFixture {
    let container: ModelContainer
    let player = QueueTestPlayer()
    let model: ReaderModel
    var context: ModelContext { container.mainContext }
    var queue: ListeningQueue { model.listeningQueue }

    init(canGenerate: @escaping (String) -> Bool = { _ in true }) throws {
        container = try ModelContainer(for: PlaylistItem.self, ListeningRecord.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        model = ReaderModel(loadModelOnInit: false, schedulerPlayer: player, audioGenerator: { text, format in
            guard canGenerate(text) else { return nil }
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
            buffer.frameLength = 1
            buffer.floatChannelData?[0][0] = 0
            return SentenceAudio(buffer: buffer, tokens: nil)
        })
        model.modelContext = container.mainContext
        model.isModelLoaded = true
    }

    func add(_ title: String, text: String? = nil) throws -> PlaylistItem {
        let item = PlaylistItem(title: title, sourceType: "text", fullText: text ?? "\(title) article.", status: "queued")
        context.insert(item)
        try context.save()
        return item
    }

    func cleanup() { queue.end(); model.stop() }

    func wait(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }

    func completeScheduledArticle() {
        // Consume the initial silence bridge as well as the article's buffers.
        for _ in 0..<100 where player.count > 0 && model.progress < 1 { player.completeNext() }
    }

    func finishCurrent() async throws {
        let id = model.currentPlaylistItemID
        for _ in 0..<200 {
            if model.currentPlaylistItemID != id || model.progress >= 1 { return }
            if player.count > 0 { player.completeNext() }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(model.currentPlaylistItemID != id || model.progress >= 1)
    }
}

@MainActor
private final class QueueTestPlayer: AudioBufferPlayer {
    private var completions: [() -> Void] = []
    private(set) var isPlaying = false
    var count: Int { completions.count }
    func schedule(_ buffer: AVAudioPCMBuffer, onComplete: @escaping () -> Void) { completions.append(onComplete) }
    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func stop() { isPlaying = false; completions = [] }
    func completeNext() { guard !completions.isEmpty else { return }; completions.removeFirst()() }
}
