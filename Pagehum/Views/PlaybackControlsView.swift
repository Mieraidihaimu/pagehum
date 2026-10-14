// Modified for Pagehum: unified application and command-line naming.
import SwiftUI

struct PlaybackControlsView: View {

    @ObservedObject var viewModel: ReaderModel
    @ObservedObject private var queue: ListeningQueue
    @State private var isExpanded = true
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var showQueue = false
    @State private var showRemainingTime = false

    init(viewModel: ReaderModel) {
        self.viewModel = viewModel
        queue = viewModel.listeningQueue
    }

    private let speeds: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0, 2.25, 2.5, 3.0]
    private let speedLabels = ["0.75x", "1x", "1.25x", "1.5x", "2x", "2.25x", "2.5x", "3x"]

    var body: some View {
        Group {
            if isExpanded {
                compactHorizontalBar
            } else {
                minimizedCircleView
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isExpanded)
    }

    // MARK: - Compact One-Horizontal Bar

    private var compactHorizontalBar: some View {
        VStack(spacing: 0) {
            // Micro-scrubber track integrated on the top edge
            scrubberTrack

            // Single horizontal controls row
            HStack(spacing: 8) {
                // 1. Playback speed pill
                speedMenuButton

                Spacer(minLength: 2)

                // 2. Skip backward 20s
                Button {
                    viewModel.skipBackward()
                } label: {
                    Image(systemName: "gobackward.20")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .accessibilityLabel("Back 20 seconds")

                // 3. Play / Pause primary button
                Button {
                    viewModel.togglePlayback()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.gradient)
                            .frame(width: 40, height: 40)
                            .shadow(color: Color.accentColor.opacity(0.35), radius: 6, y: 2)

                        if viewModel.isPreparing {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else if viewModel.isPlaying {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .offset(x: 1.5)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")

                // 4. Skip forward 20s
                Button {
                    viewModel.skipForward()
                } label: {
                    Image(systemName: "goforward.20")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .accessibilityLabel("Forward 20 seconds")

                Spacer(minLength: 2)

                // 5. Time display
                timeBadge

                // 6. Queue or Restart action
                trailingActionButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(height: 50)
        }
        .frame(maxWidth: 440)
        .background(
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(Color.platformGroupedBackground.opacity(0.12))
            }
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.16), radius: 14, y: 5)
        .overlay(alignment: .top) {
            if isDragging {
                Text(dragTooltipText)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.85), in: Capsule())
                    .offset(y: -36)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showQueue) {
            ListeningQueueSheet(viewModel: viewModel, queue: queue)
        }
        #endif
        .gesture(
            DragGesture(minimumDistance: 24, coordinateSpace: .local)
                .onEnded { val in
                    if val.translation.height > 24 {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isExpanded = false
                        }
                    }
                }
        )
    }

    // MARK: - Scrubber Track

    private var scrubberTrack: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background track
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: isDragging ? 5 : 3)

                // Progress track
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, min(geo.size.width, geo.size.width * displayProgress)), height: isDragging ? 5 : 3)

                // Drag indicator thumb
                if isDragging {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .frame(width: 9, height: 9)
                        .offset(x: max(0, min(geo.size.width - 9, geo.size.width * displayProgress - 4.5)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
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
        .frame(height: isDragging ? 5 : 3)
    }

    // MARK: - Subcomponents

    private var speedMenuButton: some View {
        Menu {
            ForEach(speeds.indices, id: \.self) { index in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.speed = speeds[index]
                    }
                } label: {
                    HStack {
                        Text(speedLabels[index])
                        if viewModel.speed == speeds[index] {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(currentSpeedLabel)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.15), in: Capsule())
        } primaryAction: {
            cycleSpeed()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Playback speed")
        .accessibilityValue(currentSpeedLabel)
    }

    private var timeBadge: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                showRemainingTime.toggle()
            }
        } label: {
            VStack(alignment: .trailing, spacing: 1) {
                Text(showRemainingTime ? "-\(remainingTimeText)" : elapsedTimeText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)

                if viewModel.isPreparing {
                    Text("Preparing")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                } else if viewModel.playbackFailureCount > 0 {
                    Text("\(viewModel.playbackFailureCount) skipped")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.orange)
                } else {
                    Text(showRemainingTime ? "remaining" : "elapsed")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Toggle elapsed or remaining time")
    }

    @ViewBuilder private var trailingActionButton: some View {
        if queue.isActive {
            Button {
                showQueue = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: queue.failure != nil ? "exclamationmark.circle.fill" : "list.bullet")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(queue.failure != nil ? .orange : Color.accentColor)
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())

                    if queue.upcoming.count > 0 && queue.failure == nil {
                        Text("\(queue.upcoming.count)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.accentColor, in: Capsule())
                            .offset(x: 4, y: -2)
                    }
                }
            }
            .accessibilityLabel("Queue")
        } else {
            Button {
                viewModel.restartFromBeginning()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Restart from beginning")
            .help("Read again from beginning")
        }
    }

    // MARK: - Minimized Circle

    private var minimizedCircleView: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isExpanded = true }
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)

                Circle()
                    .stroke(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 3))

                Circle()
                    .trim(from: 0, to: viewModel.progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 48, height: 48)
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        }
        .accessibilityLabel("Show playback controls")
        .accessibilityValue(viewModel.isPlaying ? "Playing" : "Paused")
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 8)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity),
            removal: .scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity)
        ))
    }

    // MARK: - Helpers

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

    private var dragTooltipText: String {
        let count = max(viewModel.sentences.count, 1)
        let target = min(Int(dragProgress * Double(count)), count - 1)
        let chars = viewModel.sentences.prefix(target).reduce(0) { $0 + $1.count }
        let elapsed = Double(chars) / Self.charsPerSecond / Double(max(viewModel.speed, 0.1))
        return "\(formatTime(elapsed)) / \(formatTime(estimatedTotal))"
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
