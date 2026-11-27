#if os(iOS)
import SwiftUI

struct PhonePlaybackControls: View {
    @ObservedObject var viewModel: ReaderModel
    @ObservedObject private var offlineAudio: OfflineAudioManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isScrubbing = false
    @State private var scrubProgress = 0.0

    init(viewModel: ReaderModel) {
        self.viewModel = viewModel
        offlineAudio = viewModel.offlineAudio
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 4) {
                    progressControl
                    HStack(spacing: 2) {
                        speedMenu
                        Spacer(minLength: 0)
                        transportButtons
                    }
                }
            } else {
                HStack(spacing: 4) {
                    speedMenu
                    progressControl
                    transportButtons
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .themeCard(cornerRadius: 14, floating: true)
        .buttonStyle(.plain)
    }

    private var transportButtons: some View {
        HStack(spacing: 0) {
            Button { viewModel.skipBackward() } label: {
                skipSymbol("gobackward")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Back 20 seconds")
            .disabled(viewModel.sentences.isEmpty || viewModel.isLoading)

            playButton

            Button { viewModel.skipForward() } label: {
                skipSymbol("goforward")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Forward 20 seconds")
            .disabled(viewModel.sentences.isEmpty || viewModel.isLoading)
        }
        .foregroundStyle(AppTheme.accentPrimary)
    }

    private func skipSymbol(_ name: String) -> some View {
        // SF Symbols has no 20-second variant of these arrows.
        Image(systemName: name)
            .font(.system(size: 22))
            .overlay {
                Text(20, format: .number)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .offset(y: 2)
            }
            .accessibilityHidden(true)
    }

    private var speedMenu: some View {
        Menu {
            PlayerSpeedOptions(speed: $viewModel.speed)
        } label: {
            Text(PlaybackSpeed.label(viewModel.speed))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(AppTheme.elevated, in: Capsule())
                .overlay(Capsule().strokeBorder(AppTheme.borderSubtle))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
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
            .controlSize(.small)
            .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 44 : nil)
            .tint(AppTheme.accentPrimaryFill)
            .accessibilityLabel("Article position")
            .accessibilityValue("\(Int(displayProgress * 100)) percent")
            .accessibilityHint("Est. \(timeText(estimatedDuration * (1 - displayProgress))) left")
            .disabled(viewModel.sentences.isEmpty || viewModel.isLoading)

            Group {
                if let id = viewModel.currentOfflineAudioID, let saving = offlineAudio.progress[id],
                   saving.state != .ready {
                    Text(saving.label)
                } else if (!viewModel.isModelLoaded && !viewModel.isCurrentAudioSaved) || viewModel.isPreparing || viewModel.isWaitingForOfflineAudio {
                    Text(viewModel.phonePlaybackStatus)
                } else if viewModel.playbackFailureCount > 0 {
                    Text("\(viewModel.playbackFailureCount) sentences skipped")
                        .foregroundStyle(AppTheme.destructiveText)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Text(timeText(estimatedDuration * displayProgress))
                                .fixedSize()
                            Spacer(minLength: 4)
                            Text("−\(timeText(estimatedDuration * (1 - displayProgress)))")
                                .fixedSize()
                        }
                        Text("−\(timeText(estimatedDuration * (1 - displayProgress)))")
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Est. \(timeText(estimatedDuration * (1 - displayProgress))) left")
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        }
        .frame(maxWidth: .infinity)
    }

    private var playButton: some View {
        Button { viewModel.togglePlayback() } label: {
            Group {
                if viewModel.isPreparing {
                    ProgressView().tint(AppTheme.onAccent)
                } else {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(AppTheme.onAccent)
                }
            }
        }
        .buttonStyle(ThemePlayButtonStyle(diameter: 44))
        .accessibilityLabel(viewModel.isPreparing ? "Cancel preparation" : viewModel.isPlaying ? "Pause" : "Play")
        .disabled(!viewModel.canPlayCurrentContent || viewModel.isLoading)
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

extension ReaderModel {
    var phonePlaybackStatus: String {
        if isWaitingForOfflineAudio { return "Open Pagehum to prepare audio" }
        if !isModelLoaded && !isCurrentAudioSaved { return "Loading voice…" }
        if isPreparing { return "Preparing audio…" }
        if isPlaying { return "Playing" }
        if progress >= 1 { return "Finished" }
        return isPaused ? "Paused" : "Ready to listen"
    }
}
#endif
