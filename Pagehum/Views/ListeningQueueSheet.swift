#if os(iOS)
import SwiftUI

/// The phone counterpart of `DesktopQueueView`: reorder, remove, or clear upcoming articles.
struct ListeningQueueSheet: View {
    @ObservedObject var viewModel: ReaderModel
    @ObservedObject var queue: ListeningQueue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let current = queue.current {
                    Section(queue.failure == nil ? "Current article" : "Needs attention") {
                        Text(current.title)
                        if let id = viewModel.currentOfflineAudioID {
                            OfflineAudioProgressView(manager: viewModel.offlineAudio, id: id)
                        }
                        if let failure = queue.failure {
                            Text(failure).font(.footnote).foregroundStyle(.orange)
                        }
                    }
                }
                Section {
                    Button("Save queue audio offline", systemImage: "arrow.down.circle") {
                        viewModel.saveQueueAudioOffline()
                    }
                    .disabled(!viewModel.isModelLoaded || !queue.isActive)
                    if queue.upcoming.isEmpty {
                        Text(queue.isActive
                             ? "This is the last article. Playback stops when it finishes."
                             : "Choose articles in Library and add them to your queue.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(queue.upcoming) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title).lineLimit(2)
                            Text(ListeningQueue.durationLabel(characters: entry.remainingCharacters, speed: viewModel.speed))
                                .font(.caption).foregroundStyle(.secondary)
                            OfflineAudioProgressView(manager: viewModel.offlineAudio,
                                                     id: OfflineAudioRequest.identifier(textID: entry.textID, voice: viewModel.selectedVoice))
                        }
                    }
                    .onMove { queue.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { queue.remove(atOffsets: $0) }
                } header: {
                    Text("Up next")
                } footer: {
                    Text("Continues automatically · Resume saved positions")
                    Text("Save every article's audio before locking your phone to keep the same voice throughout the queue.")
                }
            }
            .navigationTitle("Up next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { EditButton().disabled(queue.upcoming.isEmpty) }
                ToolbarItem(placement: .bottomBar) {
                    Button("Clear upcoming", role: .destructive) { queue.clearUpcoming() }
                        .disabled(queue.upcoming.isEmpty)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}
#endif
