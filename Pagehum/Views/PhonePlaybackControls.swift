#if os(iOS)
import SwiftUI

struct PhonePlaybackControls: View {
    @ObservedObject var viewModel: ReaderModel
    @ObservedObject private var queue: ListeningQueue
    @ObservedObject private var offlineAudio: OfflineAudioManager
    @State private var isScrubbing = false
    @State private var scrubProgress = 0.0
    @State private var showsQueue = false

    init(viewModel: ReaderModel) {
        self.viewModel = viewModel
        queue = viewModel.listeningQueue
        offlineAudio = viewModel.offlineAudio
    }

    private var status: String {
        if viewModel.isWaitingForOfflineAudio { return "Open Pagehum to prepare audio" }
        if !viewModel.isModelLoaded && !viewModel.isCurrentAudioSaved { return "Loading voice…" }
        if viewModel.isPreparing { return "Preparing audio…" }
        if viewModel.isPlaying { return "Playing" }
        if viewModel.progress >= 1 { return "Finished" }
        return viewModel.isPaused ? "Paused" : "Ready to listen"
    }

    var body: some View {
        HStack(spacing: 8) {
            playButton
            speedMenu
            progressControl
            actionsMenu
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.06)))
        .buttonStyle(.plain)
        .sheet(isPresented: $showsQueue) {
            ListeningQueueSheet(viewModel: viewModel, queue: queue)
                .presentationDragIndicator(.visible)
        }
    }

    private var speedMenu: some View {
        Menu {
            Picker("Playback speed", selection: $viewModel.speed) {
                ForEach([Float(0.75), 1, 1.25, 1.5, 2, 2.25, 2.5, 3], id: \.self) { speed in
                    Text("\(speed.formatted())×").tag(speed)
                }
            }
        } label: {
            Text("\(viewModel.speed.formatted())×")
                .font(.callout.weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 52, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Playback speed")
        .accessibilityValue("\(viewModel.speed.formatted()) times")
    }

    private var progressControl: some View {
        VStack(alignment: .leading, spacing: 0) {
            Slider(value: progressBinding, in: 0...1, onEditingChanged: { editing in
                if editing { scrubProgress = viewModel.progress }
                isScrubbing = editing
                if !editing { seek(to: scrubProgress) }
            })
            .frame(minHeight: 28)
            .accessibilityLabel("Article position")
            .accessibilityValue("\(Int(displayProgress * 100)) percent")
            .accessibilityHint("Est. \(timeText(estimatedDuration * (1 - displayProgress))) left")
            .disabled(viewModel.sentences.isEmpty || viewModel.isLoading)

            Group {
                if let id = viewModel.currentOfflineAudioID, let saving = offlineAudio.progress[id],
                   saving.state != .ready {
                    Text(saving.label)
                } else if (!viewModel.isModelLoaded && !viewModel.isCurrentAudioSaved) || viewModel.isPreparing || viewModel.isWaitingForOfflineAudio {
                    Text(status)
                } else if viewModel.playbackFailureCount > 0 {
                    Text("\(viewModel.playbackFailureCount) sentences skipped")
                        .foregroundStyle(.orange)
                } else {
                    Text("\(timeText(estimatedDuration * displayProgress)) / \(timeText(estimatedDuration))")
                        .accessibilityLabel("Est. \(timeText(estimatedDuration * (1 - displayProgress))) left")
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private var actionsMenu: some View {
        Menu {
            Text(status)
            if let id = viewModel.currentOfflineAudioID {
                OfflineAudioMenuActions(manager: offlineAudio, id: id, canSave: viewModel.isModelLoaded,
                                        canRemove: !viewModel.isPlaying && !viewModel.isPreparing,
                                        save: viewModel.saveCurrentAudioOffline)
            }
            if viewModel.playbackFailureCount > 0 {
                Text("\(viewModel.playbackFailureCount) sentences skipped")
            }
            Divider()
            Button("Back 20 seconds", systemImage: "gobackward") {
                viewModel.skipBackward()
            }
            .disabled(viewModel.sentences.isEmpty || viewModel.isLoading)
            Button("Forward 20 seconds", systemImage: "goforward") {
                viewModel.skipForward()
            }
            .disabled(viewModel.sentences.isEmpty || viewModel.isLoading)
            Button("Restart from beginning", systemImage: "arrow.counterclockwise") {
                viewModel.restartFromBeginning()
            }
            .disabled(!viewModel.canPlayCurrentContent || viewModel.isLoading)
            Divider()
            Button("Up next, \(queue.upcoming.count) articles", systemImage: "list.bullet") {
                showsQueue = true
            }
        } label: {
            Image(systemName: queue.failure != nil || viewModel.playbackFailureCount > 0
                  ? "exclamationmark.circle" : "ellipsis")
                .font(.title3)
                .foregroundStyle(queue.failure != nil || viewModel.playbackFailureCount > 0
                                 ? Color.orange : Color.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Playback actions")
        .accessibilityValue(queue.failure ?? status)
    }

    private var playButton: some View {
        Button { viewModel.togglePlayback() } label: {
            ZStack {
                Circle().fill(Color.accentColor.gradient)
                if viewModel.isPreparing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3.weight(.semibold)).foregroundStyle(.white)
                }
            }
            .frame(width: 44, height: 44)
        }
        .accessibilityLabel(viewModel.isPreparing ? "Cancel preparation" : viewModel.isPlaying ? "Pause" : "Play")
        .disabled(!viewModel.canPlayCurrentContent || viewModel.isLoading)
        .opacity(!viewModel.canPlayCurrentContent || viewModel.isLoading ? 0.4 : 1)
    }

    private var displayProgress: Double { isScrubbing ? scrubProgress : min(1, max(0, viewModel.progress)) }

    private var progressBinding: Binding<Double> {
        Binding(get: { displayProgress }, set: { value in
            if isScrubbing { scrubProgress = value }
            else { seek(to: value) } // VoiceOver adjusts the slider without a drag session.
        })
    }

    private func seek(to fraction: Double) {
        guard !viewModel.sentences.isEmpty, fraction.isFinite else { return }
        let count = viewModel.sentences.count
        viewModel.seekToSentence(min(count - 1, max(0, Int(fraction * Double(count)))))
    }

    private var estimatedDuration: Double {
        Double(viewModel.sentences.reduce(0) { $0 + $1.count }) / 13 / Double(max(viewModel.speed, 0.1))
    }

    private func timeText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
#endif
