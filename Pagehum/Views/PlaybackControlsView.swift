// Modified for Pagehum: unified application and command-line naming.
import SwiftUI

struct PlaybackControlsView: View {

    @ObservedObject var viewModel: ReaderModel
    @ObservedObject private var queue: ListeningQueue
    @State private var isExpanded = true
    @State private var autoMinimizeTask: Task<Void, Never>?
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var showQueue = false

    init(viewModel: ReaderModel) {
        self.viewModel = viewModel
        queue = viewModel.listeningQueue
    }

    private let speeds: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0, 2.25, 2.5, 3.0]
    private let speedLabels = ["0.75x", "1x", "1.25x", "1.5x", "2x", "2.25x", "2.5x", "3x"]

    var body: some View {
        Group {
            if isExpanded {
                expandedView
            } else {
                minimizedCircleView
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isExpanded)
        .onChange(of: viewModel.isPlaying) { _, playing in
            if playing { scheduleAutoMinimize() }
        }
    }

    // MARK: - Expanded

    private var expandedView: some View {
        VStack(spacing: 8) {
            #if os(iOS)
            if queue.isActive { queueStrip.padding(.top, 10) }
            #endif
            VStack(spacing: 2) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.quaternary)
                            .frame(height: isDragging ? 6 : 4)
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: max(0, geo.size.width * displayProgress), height: isDragging ? 6 : 4)

                        Circle()
                            .fill(.white)
                            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                            .frame(width: 14, height: 14)
                            .offset(x: max(0, min(geo.size.width - 14, geo.size.width * displayProgress - 7)))
                            .opacity(isDragging ? 1 : 0)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDragging = true
                                dragProgress = max(0, min(1, value.location.x / geo.size.width))
                            }
                            .onEnded { _ in
                                let count = max(viewModel.sentences.count, 1)
                                let target = min(Int(dragProgress * Double(count)), count - 1)
                                viewModel.seekToSentence(target)
                                isDragging = false
                            }
                    )
                }
                .frame(height: 20)

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

            // Transport + Speed
            HStack(spacing: 0) {
                Button { cycleSpeed() } label: {
                    Text(currentSpeedLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.fill.tertiary, in: Capsule())
                }
                .accessibilityLabel("Playback speed")
                .accessibilityValue(currentSpeedLabel)

                Spacer()

                Button { viewModel.skipBackward() } label: {
                    Image(systemName: "gobackward.20")
                        .font(.title3)
                        .frame(width: 44, height: 44)
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
                    .frame(width: 44, height: 44)
                }
                .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")

                Spacer()

                Button { viewModel.skipForward() } label: {
                    Image(systemName: "goforward.20")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Forward 20 seconds")

                Spacer()

                Button { viewModel.restartFromBeginning() } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title3)
                        .frame(width: 56, height: 44)
                }
                .accessibilityLabel("Read again from beginning")
                .help("Read again from beginning")
            }
            .foregroundStyle(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: 460)
        .frame(maxHeight: queue.isActive ? 150 : 112)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
        )
        #if os(iOS)
        .sheet(isPresented: $showQueue) { ListeningQueueSheet(viewModel: viewModel, queue: queue) }
        #endif
        .transition(.asymmetric(
            insertion: .scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity),
            removal: .scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity)
        ))
    }

    // MARK: - Minimized Circle

    private var minimizedCircleView: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isExpanded = true }
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)

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
        .transition(.asymmetric(
            insertion: .scale(scale: 0.5, anchor: .bottomTrailing).combined(with: .opacity),
            removal: .scale(scale: 0.5, anchor: .bottomTrailing).combined(with: .opacity)
        ))
    }

    // MARK: - Helpers

    @ViewBuilder private var queueStrip: some View {
        if let failure = queue.failure {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                Text(failure).lineLimit(2)
                Spacer(minLength: 0)
                Button("Retry") { queue.retry() }
                    .disabled(!viewModel.isModelLoaded || viewModel.isLoading)
                Button("Skip") { queue.skip() }
            }
            .font(.caption.weight(.semibold))
        } else {
            HStack(spacing: 12) {
                Button { showQueue = true } label: {
                    Label("Up next · \(queue.upcoming.count)", systemImage: "list.bullet")
                }
                Spacer()
                Button { queue.skip() } label: {
                    Label("Next article", systemImage: "forward.end")
                }
                .disabled(viewModel.isLoading)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
        }
    }

    private var currentSpeedLabel: String {
        speedLabels[speeds.firstIndex(of: viewModel.speed) ?? 1]
    }

    private func cycleSpeed() {
        let currentIndex = speeds.firstIndex(of: viewModel.speed) ?? 1
        let nextIndex = (currentIndex + 1) % speeds.count
        withAnimation(.spring(response: 0.3)) { viewModel.speed = speeds[nextIndex] }
    }

    private var displayProgress: Double {
        isDragging ? dragProgress : viewModel.progress
    }

    private static let charsPerSecond: Double = 13

    private var estimatedTotal: TimeInterval {
        let totalChars = viewModel.sentences.reduce(0) { $0 + $1.count }
        return Double(totalChars) / Self.charsPerSecond / Double(max(viewModel.speed, 0.1))
    }

    private var estimatedElapsed: TimeInterval {
        let idx = min(viewModel.currentSentenceIndex, viewModel.sentences.count)
        let chars = viewModel.sentences.prefix(idx).reduce(0) { $0 + $1.count }
        return Double(chars) / Self.charsPerSecond / Double(max(viewModel.speed, 0.1))
    }

    private var elapsedTimeText: String { formatTime(estimatedElapsed) }
    private var remainingTimeText: String { formatTime(estimatedTotal - estimatedElapsed) }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func scheduleAutoMinimize() {
        autoMinimizeTask?.cancel()
        autoMinimizeTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if viewModel.isPlaying && isExpanded {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isExpanded = false }
                }
            }
        }
    }
}
