// Modified for Pagehum: unified application and command-line naming.
import SwiftUI

struct PlaybackControlsView: View {

    @ObservedObject var viewModel: ReaderModel
    @State private var isExpanded = true
    @State private var autoMinimizeTask: Task<Void, Never>?
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var characterOffsets: [Int] = [0]
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let speeds: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0, 2.25, 2.5, 3.0]

    var body: some View {
        Group {
            if isExpanded {
                expandedView
            } else {
                minimizedCircleView
            }
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: isExpanded)
        .onChange(of: viewModel.isPlaying, initial: true) { _, playing in
            if playing { scheduleAutoMinimize() }
            else {
                autoMinimizeTask?.cancel()
                isExpanded = true
            }
        }
        .onChange(of: viewModel.sentences, initial: true) { _, sentences in
            var offsets = [0]
            for sentence in sentences { offsets.append(offsets.last! + sentence.count) }
            characterOffsets = offsets
        }
        .onChange(of: voiceOverEnabled) { _, enabled in
            if enabled { autoMinimizeTask?.cancel(); isExpanded = true }
        }
        .onChange(of: dynamicTypeSize) { _, size in
            if size.isAccessibilitySize { autoMinimizeTask?.cancel(); isExpanded = true }
        }
        .onDisappear { autoMinimizeTask?.cancel() }
    }

    // MARK: - Expanded

    private var expandedView: some View {
        VStack(spacing: 8) {
            VStack(spacing: 2) {
                Slider(value: Binding(
                    get: { displayProgress },
                    set: { value in
                        dragProgress = value
                        // VoiceOver and keyboard adjustments can bypass dragging.
                        if !isDragging { seek(to: value) }
                    }
                ), in: 0...1, step: 1 / Double(max(viewModel.sentences.count, 1)), onEditingChanged: { editing in
                    if editing {
                        dragProgress = viewModel.progress
                        isDragging = true
                        autoMinimizeTask?.cancel()
                    } else {
                        isDragging = false
                        seek(to: dragProgress)
                        scheduleAutoMinimize()
                    }
                })
                .accessibilityLabel("Article position")
                .accessibilityValue("\(Int(displayProgress * 100)) percent")
                .disabled(viewModel.sentences.isEmpty || viewModel.isLoading)

                HStack {
                    Text(elapsedTimeText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if viewModel.isPreparing {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text("Preparing").font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    } else if viewModel.playbackFailureCount > 0 {
                        Text("\(viewModel.playbackFailureCount) skipped")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if viewModel.isGenerating {
                        Text("Generating")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("-\(remainingTimeText)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            // Stack the speed menu above transport at accessibility text sizes.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 16))
            layout {
                Menu {
                    Picker("Playback speed", selection: $viewModel.speed) {
                        ForEach(speeds, id: \.self) { speed in
                            Text(speedLabel(speed)).tag(speed)
                        }
                    }
                } label: {
                    Text(currentSpeedLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.fill.tertiary, in: Capsule())
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Playback speed")
                .accessibilityValue(currentSpeedLabel)

                HStack(spacing: 0) {
                    Button { viewModel.skipBackward() } label: {
                        Image(systemName: "gobackward.20")
                            .font(.title3)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Back 20 seconds")

                    Spacer()

                    Button { viewModel.togglePlayback() } label: {
                        Group {
                            if viewModel.isPreparing {
                                ProgressView()
                                    .controlSize(.large)
                            } else {
                                Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .symbolRenderingMode(.hierarchical)
                            }
                        }
                        .font(.system(size: 44))
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(viewModel.isPreparing ? "Cancel audio preparation" : viewModel.isPlaying ? "Pause" : "Play")
                    .disabled(!viewModel.isModelLoaded)

                    Spacer()

                    Button { viewModel.skipForward() } label: {
                        Image(systemName: "goforward.20")
                            .font(.title3)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Forward 20 seconds")

                    Spacer()

                    Button { viewModel.restartFromBeginning() } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.title3)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Read again from beginning")
                    .help("Read again from beginning")
                    .disabled(!viewModel.isModelLoaded)
                }
            }
            .foregroundStyle(.primary)
            .disabled(viewModel.sentences.isEmpty || viewModel.isLoading)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: 460)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 20).fill(Color.platformGroupedBackground)
            } else {
                RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
        )
        .transition(reduceMotion ? .opacity : .asymmetric(
            insertion: .scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity),
            removal: .scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity)
        ))
    }

    // MARK: - Minimized Circle

    private var minimizedCircleView: some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8)) { isExpanded = true }
        } label: {
            ZStack {
                if reduceTransparency {
                    Circle().fill(Color.platformGroupedBackground)
                } else {
                    Circle().fill(.ultraThinMaterial)
                }

                Circle()
                    .stroke(Color.platformGray, style: StrokeStyle(lineWidth: 3))

                Circle()
                    .trim(from: 0, to: viewModel.progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 56, height: 56)
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        }
        .accessibilityLabel("Show playback controls")
        .accessibilityValue(viewModel.isPlaying ? "Playing" : "Paused")
        .frame(maxWidth: .infinity, alignment: .trailing)
        .transition(reduceMotion ? .opacity : .asymmetric(
            insertion: .scale(scale: 0.5, anchor: .bottomTrailing).combined(with: .opacity),
            removal: .scale(scale: 0.5, anchor: .bottomTrailing).combined(with: .opacity)
        ))
    }

    // MARK: - Helpers

    private var currentSpeedLabel: String { speedLabel(viewModel.speed) }

    private func speedLabel(_ speed: Float) -> String {
        "\(speed.formatted(.number.precision(.fractionLength(0...2))))×"
    }

    private var displayProgress: Double {
        min(1, max(0, isDragging ? dragProgress : viewModel.progress))
    }

    private func seek(to progress: Double) {
        guard !viewModel.sentences.isEmpty, !viewModel.isLoading else { return }
        let target = min(viewModel.sentences.count - 1, max(0, Int((progress * Double(viewModel.sentences.count)).rounded())))
        viewModel.seekToSentence(target)
    }

    private static let charsPerSecond: Double = 13

    private var estimatedTotal: TimeInterval {
        Double(characterOffsets.last ?? 0) / Self.charsPerSecond / Double(max(viewModel.speed, 0.1))
    }

    private var estimatedElapsed: TimeInterval {
        if !isDragging && viewModel.progress >= 1 { return estimatedTotal }
        let index = isDragging
            ? min(max(0, viewModel.sentences.count - 1), Int(displayProgress * Double(viewModel.sentences.count)))
            : viewModel.currentSentenceIndex
        let boundedIndex = min(max(0, index), characterOffsets.count - 1)
        return Double(characterOffsets[boundedIndex]) / Self.charsPerSecond / Double(max(viewModel.speed, 0.1))
    }

    private var elapsedTimeText: String { formatTime(estimatedElapsed) }
    private var remainingTimeText: String { formatTime(estimatedTotal - estimatedElapsed) }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func scheduleAutoMinimize() {
        autoMinimizeTask?.cancel()
        guard viewModel.isPlaying, !isDragging, !voiceOverEnabled, !dynamicTypeSize.isAccessibilitySize else { return }
        autoMinimizeTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if viewModel.isPlaying && isExpanded && !isDragging && !voiceOverEnabled && !dynamicTypeSize.isAccessibilitySize {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8)) { isExpanded = false }
                }
            }
        }
    }
}
