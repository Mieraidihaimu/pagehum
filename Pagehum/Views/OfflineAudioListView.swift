import SwiftData
import SwiftUI

struct OfflineAudioSettingsLabel: View {
    var body: some View {
        Label("Offline Audio", systemImage: "arrow.down.circle")
    }
}

struct OfflineAudioListView: View {
    @ObservedObject var viewModel: ReaderModel
    @ObservedObject private var manager: OfflineAudioManager
    @ObservedObject private var queue: ListeningQueue
    @Query(sort: \PlaylistItem.dateAdded, order: .reverse) private var items: [PlaylistItem]
    @State private var selecting = false
    @State private var selection: Set<String> = []
    @State private var confirmingRemoval = false
    @State private var removalError = false
    @State private var showPlayer = false
    private var openPlayer: (() -> Void)?

    init(viewModel: ReaderModel, openPlayer: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.openPlayer = openPlayer
        manager = viewModel.offlineAudio
        queue = viewModel.listeningQueue
    }

    private var entries: [OfflineAudioLibrary.Entry] {
        OfflineAudioLibrary.entries(records: manager.store.allRecords(), items: items, preferredVoice: viewModel.selectedVoice)
    }

    private var appending: Bool {
        queue.isActive || (viewModel.progress < 1 && (viewModel.isPlaying || viewModel.isPaused || viewModel.isPreparing))
    }

    var body: some View {
        let entries = entries
        let selected = entries.filter { selection.contains($0.id) }
        let playable = selected.filter { $0.canPlay && !isQueued($0) }
        let removable = selected.filter { !isInUse($0) }

        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("^[\(entries.count) article](inflect: true)").font(.headline)
                    Text("Select saved articles to listen or free up storage.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button(selecting ? "Cancel" : "Select") {
                    selecting.toggle()
                    selection = []
                }
                .disabled(entries.isEmpty)
            }
            .padding(16)

            if entries.isEmpty {
                ContentUnavailableView("No offline audio", systemImage: "arrow.down.circle", description: Text("Save audio from your library or player to listen offline."))
            } else {
                List(entries) { entry in
                    audioRow(entry)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Offline Audio")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showPlayer) {
            PhoneReaderView(viewModel: viewModel)
        }
        #endif
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selecting {
                VStack(spacing: 12) {
                    HStack {
                        Text("\(selected.count) selected").font(.headline)
                        Spacer()
                        Button(selection.count == entries.count ? "Deselect all" : "Select all") {
                            selection = selection.count == entries.count ? [] : Set(entries.map(\.id))
                        }
                    }
                    HStack(spacing: 12) {
                        Button(role: .destructive) { confirmingRemoval = true } label: {
                            Label("Delete \(removable.count)", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .disabled(removable.isEmpty)
                        Button { play(playable) } label: {
                            Label(appending ? "Add \(playable.count) to queue" : "Play \(playable.count)", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(playable.isEmpty || viewModel.isLoading)
                    }
                    if selected.contains(where: { !$0.canPlay }) {
                        Text("Playback requires a completed save and its article in your library.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if removable.count < selected.count {
                        Text("Audio in use is kept until you finish listening or remove it from the queue.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .controlSize(.large)
                .padding(16)
                .background(.bar)
            }
        }
        .confirmationDialog(Text(AttributedString(localized: "Delete offline audio for ^[\(removable.count) article](inflect: true)?")), isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Delete offline audio", role: .destructive) { remove(removable) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All saved voices for these articles will be deleted. The articles stay in your library.")
        }
        .alert("Some audio couldn’t be deleted", isPresented: $removalError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The remaining saves are still selected. Try deleting them again.")
        }
        .onChange(of: entries.map(\.id)) { _, ids in
            selection.formIntersection(ids)
            if ids.isEmpty { selecting = false }
        }
    }

    @ViewBuilder
    private func audioRow(_ entry: OfflineAudioLibrary.Entry) -> some View {
        if selecting {
            Button { toggleSelection(entry.id) } label: { audioRowContent(entry) }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(entry.title)
                .accessibilityValue(selection.contains(entry.id) ? "Selected" : "Not selected")
                .accessibilityAddTraits(selection.contains(entry.id) ? .isSelected : [])
        } else {
            audioRowContent(entry)
        }
    }

    private func audioRowContent(_ entry: OfflineAudioLibrary.Entry) -> some View {
        HStack(spacing: 12) {
            if selecting {
                Image(systemName: selection.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title).font(.headline).lineLimit(2)
                OfflineAudioProgressView(manager: manager, id: entry.displayRecord.request.id)
                if entry.records.count > 1 {
                    Text("^[\(entry.records.count) saved voice](inflect: true)").font(.caption).foregroundStyle(.secondary)
                }
                if entry.item == nil {
                    Text("Article no longer in your library").font(.caption).foregroundStyle(.secondary)
                } else if isQueued(entry) {
                    Text("In listening queue").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if !selecting, entry.canPlay {
                Button { play([entry]) } label: {
                    Image(systemName: "play.circle.fill").font(.title2).frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isLoading)
                .accessibilityLabel("Play \(entry.title)")
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func toggleSelection(_ id: String) {
        if !selection.insert(id).inserted { selection.remove(id) }
    }

    private func isQueued(_ entry: OfflineAudioLibrary.Entry) -> Bool {
        queue.current?.textID == entry.id || queue.upcoming.contains { $0.textID == entry.id }
    }

    private func isInUse(_ entry: OfflineAudioLibrary.Entry) -> Bool {
        isQueued(entry) || ((viewModel.isPlaying || viewModel.isPaused || viewModel.isPreparing) &&
            OfflineAudioRequest.identifier(textID: entry.id, voice: viewModel.selectedVoice) == viewModel.currentOfflineAudioID)
    }

    private func play(_ entries: [OfflineAudioLibrary.Entry]) {
        queue.enqueue(entries.compactMap(\.item))
        selection = []
        selecting = false
        if let openPlayer { openPlayer() }
        else { showPlayer = true }
    }

    private func remove(_ entries: [OfflineAudioLibrary.Entry]) {
        for entry in entries where !isInUse(entry) {
            for record in entry.records { manager.remove(record.request.id) }
        }
        let remaining = Set(self.entries.map(\.id))
        selection.formIntersection(remaining)
        removalError = entries.contains { remaining.contains($0.id) }
        if selection.isEmpty { selecting = false }
    }
}
