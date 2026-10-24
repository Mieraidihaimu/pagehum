#if os(iOS)
import SwiftUI

/// Keeps the current listen and its queue within reach while browsing other tabs.
struct PhoneMiniPlayer: View {
    @ObservedObject var viewModel: ReaderModel
    @ObservedObject private var queue: ListeningQueue
    var openReader: () -> Void
    @State private var showsQueue = false

    init(viewModel: ReaderModel, openReader: @escaping () -> Void) {
        self.viewModel = viewModel
        self.openReader = openReader
        queue = viewModel.listeningQueue
    }

    private var status: LocalizedStringKey {
        if queue.failure != nil { return "Needs attention" }
        if viewModel.isWaitingForOfflineAudio { return "Open Pagehum to prepare audio" }
        if viewModel.isPreparing { return "Preparing audio…" }
        if viewModel.isPlaying { return "Playing" }
        if viewModel.progress >= 1 { return "Finished" }
        return viewModel.isPaused ? "Paused" : "Ready to listen"
    }

    var body: some View {
        if let title = queue.current?.title ?? viewModel.content?.title {
            HStack(spacing: 8) {
                Button(action: openReader) {
                    HStack(spacing: 10) {
                        Image(systemName: viewModel.isPlaying ? "waveform" : "headphones")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 36, height: 40)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(status).font(.caption).foregroundStyle(queue.failure == nil ? Color.secondary : .orange)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Open Listen: \(title)")
                .accessibilityValue(Text(status))

                Button { viewModel.togglePlayback() } label: {
                    Group {
                        if viewModel.isPreparing { ProgressView() }
                        else {
                            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title3)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .disabled(!viewModel.canPlayCurrentContent || viewModel.isLoading)
                .accessibilityLabel(viewModel.isPreparing ? "Cancel preparation" : viewModel.isPlaying ? "Pause" : "Play")

                if queue.isActive {
                    PhoneQueueButton(count: queue.upcoming.count, needsAttention: queue.failure != nil) {
                        showsQueue = true
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.06)))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .sheet(isPresented: $showsQueue) {
                ListeningQueueSheet(viewModel: viewModel, queue: queue)
            }
        }
    }
}

/// The number always excludes the current article, including zero on the last one.
struct PhoneQueueButton: View {
    let count: Int
    var needsAttention = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: needsAttention ? "exclamationmark.circle" : "list.bullet")
                Text(count.formatted()).font(.caption.weight(.semibold).monospacedDigit())
            }
            .foregroundStyle(needsAttention ? Color.orange : Color.accentColor)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Listening queue")
        .accessibilityValue(Text("^[\(count) article](inflect: true) up next"))
        .accessibilityHint(needsAttention ? "Playback needs attention. Open listening queue." : "Reorder or remove upcoming articles")
    }
}
#endif
