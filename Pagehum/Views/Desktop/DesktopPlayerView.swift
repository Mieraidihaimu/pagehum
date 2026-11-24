// Modified for Pagehum: unified application and command-line naming.
#if os(macOS)
import SwiftUI

struct DesktopPlayerView: View {
    @ObservedObject var viewModel: ReaderModel
    @ObservedObject var queue: ListeningQueue
    var openReader: () -> Void
    @State private var seeking = false
    @State private var seekProgress = 0.0
    @State private var remainingCharacterCounts: [Int] = []
    @State private var showQueue = false
    @State private var showSpeedPopover = false

    private static let minSpeed: Float = 0.75
    private static let maxSpeed: Float = 3.0
    private static let speedStep: Float = 0.05

    private var progress: Double { min(1, max(0, viewModel.progress)) }

    private var remainingTimeLabel: String {
        guard !viewModel.sentences.isEmpty else { return "No text to read" }
        if !seeking && progress >= 1 { return "Finished" }
        let index = seeking
            ? min(viewModel.sentences.count - 1, max(0, Int(seekProgress * Double(viewModel.sentences.count))))
            : min(viewModel.sentences.count, max(0, viewModel.currentSentenceIndex))
        guard remainingCharacterCounts.indices.contains(index) else { return "Estimating…" }

        // Use the same text-rate estimate as the existing playback controls.
        // Actual duration varies by voice, punctuation, and audio preparation.
        let seconds = Double(remainingCharacterCounts[index]) / 13 / Double(max(viewModel.speed, 0.1))
        guard seconds > 0 else { return "Finished" }
        if seconds < 60 { return "Under 1 min left (est.)" }
        let minutes = Int(ceil(seconds / 60))
        if minutes < 60 { return "About \(minutes) min left" }
        let remainder = minutes % 60
        return remainder == 0
            ? "About \(minutes / 60) hr left"
            : "About \(minutes / 60) hr \(remainder) min left"
    }
    private var status: String {
        if queue.failure != nil { return "Queue paused" }
        if !viewModel.isModelLoaded { return "Loading voice engine…" }
        if viewModel.isPreparing { return "Preparing audio…" }
        if viewModel.playbackFailureCount > 0 { return "\(viewModel.playbackFailureCount) sentences skipped" }
        if progress >= 1 { return "Finished" }
        return viewModel.isPlaying ? "Playing" : "Paused"
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                leftZone
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                centerTransport
                    .fixedSize(horizontal: true, vertical: false)

                rightZone
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
            }

            HStack(spacing: 12) {
                Text("\(Int((seeking ? seekProgress : progress) * 100))%")
                    .frame(width: 36, alignment: .leading)
                Slider(value: Binding(get: { seeking ? seekProgress : progress }, set: { value in
                    seekProgress = value
                    // Keyboard changes do not always enter the dragging lifecycle.
                    if !seeking { seek(to: value) }
                }), in: 0...1, onEditingChanged: { editing in
                    if editing { seekProgress = progress; seeking = true }
                    else { seeking = false; seek(to: seekProgress) }
                })
                .controlSize(.small)
                .tint(AppTheme.accentPrimaryFill)
                .accessibilityLabel("Article position")
                .accessibilityValue("\(Int((seeking ? seekProgress : progress) * 100)) percent")
                .disabled(viewModel.sentences.isEmpty || viewModel.isLoading)
                Text(remainingTimeLabel)
                    .fixedSize(horizontal: true, vertical: false)
                    .help("Estimated listening time at \(PlaybackSpeed.label(viewModel.speed)), based on the remaining text. Updates as sentences advance; actual duration varies by voice and pauses.")
                    .accessibilityLabel("Estimated time remaining")
                    .accessibilityValue(remainingTimeLabel)
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(DesktopStyle.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(AppTheme.playerSurface)
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle().fill(AppTheme.playerBorder).frame(height: 1)
                Rectangle().fill(AppTheme.darkTopHighlight).frame(height: 1)
            }
        }
        .shadow(color: AppTheme.floatingShadow, radius: 10, x: 0, y: -2)
        .onChange(of: viewModel.sentences, initial: true) { _, sentences in
            // Cache suffix lengths once per article, rather than recounting the
            // entire remaining text on every word-highlight update.
            var counts = Array(repeating: 0, count: sentences.count + 1)
            for index in sentences.indices.reversed() {
                counts[index] = counts[index + 1] + sentences[index].count
            }
            remainingCharacterCounts = counts
        }
    }

    private var leftZone: some View {
        Button(action: openReader) {
            HStack(spacing: 10) {
                Image(systemName: viewModel.content?.source.webURL != nil ? "globe" : "doc.text")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.accentPrimarySubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.content?.title ?? "Reader")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("\(status) · \(DesktopStyle.voiceLabel(viewModel.selectedVoice))")
                        .font(.system(size: 11))
                        .foregroundStyle(queue.failure != nil ? AppTheme.destructiveText : DesktopStyle.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show article")
        .accessibilityLabel("Show article: \(viewModel.content?.title ?? "Reader")")
    }

    private var centerTransport: some View {
        HStack(spacing: 8) {
            PlayerDockIconButton(
                systemImage: "gobackward.20",
                symbolSize: 16,
                helpText: "Back 20 seconds",
                tint: AppTheme.accentPrimary
            ) {
                viewModel.skipBackward()
            }
            .disabled(viewModel.sentences.isEmpty || viewModel.isLoading)

            Button { viewModel.togglePlayback() } label: {
                Group {
                    if viewModel.isPreparing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
            }
            .buttonStyle(ThemePlayButtonStyle(diameter: 40))
            .help(viewModel.isPlaying ? "Pause" : "Play")
            .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
            .disabled(!viewModel.canPlayCurrentContent || viewModel.isLoading)

            PlayerDockIconButton(
                systemImage: "goforward.20",
                symbolSize: 16,
                helpText: "Forward 20 seconds",
                tint: AppTheme.accentPrimary
            ) {
                viewModel.skipForward()
            }
            .disabled(viewModel.sentences.isEmpty || viewModel.isLoading)

            if queue.isActive {
                PlayerDockIconButton(
                    systemImage: "forward.end.fill",
                    symbolSize: 14,
                    helpText: "Next article",
                    tint: AppTheme.accentPrimary
                ) {
                    queue.skip()
                }
                .disabled(queue.upcoming.isEmpty || viewModel.isLoading)
            }
        }
    }

    private var rightZone: some View {
        HStack(spacing: 6) {
            Button { showSpeedPopover.toggle() } label: {
                Text(PlaybackSpeed.label(viewModel.speed))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.horizontal, 10)
                    .frame(minWidth: 52, minHeight: 28)
                    .background(AppTheme.elevated, in: Capsule())
                    .overlay(Capsule().strokeBorder(AppTheme.borderSubtle, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Playback speed")
            .accessibilityLabel("Playback speed")
            .accessibilityValue(PlaybackSpeed.label(viewModel.speed))
            .popover(isPresented: $showSpeedPopover, arrowEdge: .top) {
                speedPopover
            }

            Button { showQueue.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 13, weight: .medium))
                    if !queue.upcoming.isEmpty {
                        Text("\(queue.upcoming.count)")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(AppTheme.accentText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(AppTheme.accentPrimarySubtle, in: Capsule())
                    }
                }
                .foregroundStyle(queue.isActive ? AppTheme.accentPrimary : DesktopStyle.secondary)
                .frame(minWidth: 28, minHeight: 28)
                .padding(.horizontal, queue.upcoming.isEmpty ? 0 : 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(queue.upcoming.isEmpty ? "Listening queue" : "Up next: \(queue.upcoming.count)")
            .accessibilityLabel("Listening queue")
            .accessibilityValue(queue.upcoming.isEmpty ? "Empty" : "\(queue.upcoming.count) upcoming")
            .popover(isPresented: $showQueue, arrowEdge: .top) {
                DesktopQueueView(viewModel: viewModel, queue: queue)
            }

            if let id = viewModel.currentOfflineAudioID {
                OfflineAudioButton(
                    manager: viewModel.offlineAudio,
                    id: id,
                    canSave: viewModel.isModelLoaded,
                    canRemove: !viewModel.isPlaying && !viewModel.isPreparing,
                    compact: true,
                    save: viewModel.saveCurrentAudioOffline
                )
                .font(.system(size: 14, weight: .medium))
                .buttonStyle(.plain)
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .foregroundStyle(DesktopStyle.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .clipped()
                .help(viewModel.offlineAudio.progress[id]?.label ?? "Save audio offline")
            }

            PlayerDockIconButton(
                systemImage: "arrow.counterclockwise",
                symbolSize: 14,
                helpText: "Restart from beginning",
                tint: DesktopStyle.secondary
            ) {
                viewModel.restartFromBeginning()
            }
            .disabled(viewModel.sentences.isEmpty || viewModel.isLoading)
        }
    }

    private var speedPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Playback speed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text(PlaybackSpeed.label(viewModel.speed))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.accentText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.accentPrimarySubtle, in: Capsule())
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                ForEach(PlaybackSpeed.settingsOptions, id: \.self) { option in
                    let isSelected = abs(viewModel.speed - option) < 0.001
                    Button {
                        viewModel.speed = option
                    } label: {
                        Text(PlaybackSpeed.label(option))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(isSelected ? AppTheme.accentText : AppTheme.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .background(isSelected ? AppTheme.accentPrimarySubtle : AppTheme.elevated,
                                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(isSelected ? AppTheme.borderAccent : AppTheme.borderSubtle, lineWidth: 1)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }

            HStack(spacing: 10) {
                Text("Fine adjust")
                    .font(.caption)
                    .foregroundStyle(DesktopStyle.secondary)
                Spacer()
                Button {
                    adjustSpeed(by: -Self.speedStep)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 26)
                        .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(AppTheme.borderSubtle))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.speed <= Self.minSpeed)
                .help("Decrease speed")
                .accessibilityLabel("Decrease speed")

                Text(PlaybackSpeed.label(viewModel.speed))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .frame(minWidth: 46)

                Button {
                    adjustSpeed(by: Self.speedStep)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 26)
                        .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(AppTheme.borderSubtle))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.speed >= Self.maxSpeed)
                .help("Increase speed")
                .accessibilityLabel("Increase speed")
            }
        }
        .padding(14)
        .frame(width: 296)
        .background(AppTheme.surface)
        .presentationBackground(AppTheme.surface)
    }

    private func adjustSpeed(by delta: Float) {
        let steps = Int(((viewModel.speed + delta) / Self.speedStep).rounded())
        let stepped = Float(steps) * Self.speedStep
        viewModel.speed = min(Self.maxSpeed, max(Self.minSpeed, stepped))
    }

    private func seek(to value: Double) {
        guard !viewModel.sentences.isEmpty else { return }
        viewModel.seekToSentence(min(viewModel.sentences.count - 1, max(0, Int(value * Double(viewModel.sentences.count)))))
    }
}

private struct PlayerDockIconButton: View {
    let systemImage: String
    var symbolSize: CGFloat = 15
    let helpText: LocalizedStringKey
    let tint: Color
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: symbolSize, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(isEnabled && isHovering ? AppTheme.elevated : .clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { isHovering = $0 }
        .help(helpText)
        .accessibilityLabel(helpText)
    }
}
#endif
