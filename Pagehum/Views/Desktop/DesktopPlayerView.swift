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
        VStack(spacing: 10) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 3) {
                    Button(action: openReader) {
                        Text(viewModel.content?.title ?? "Reader")
                            .font(.system(size: 13, weight: .medium)).lineLimit(1)
                    }
                    .buttonStyle(.plain).help("Show article")
                    Text("\(status) · \(DesktopStyle.voiceLabel(viewModel.selectedVoice))")
                        .font(.caption).foregroundStyle(DesktopStyle.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Button { viewModel.skipBackward() } label: {
                        Image(systemName: "gobackward.20").font(.system(size: 19)).frame(width: 32, height: 36)
                    }.help("Back 20 seconds").accessibilityLabel("Back 20 seconds")
                    Button { viewModel.togglePlayback() } label: {
                        Group {
                            if viewModel.isPreparing { ProgressView().controlSize(.small) }
                            else { Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill") }
                        }
                        .frame(width: 40, height: 40)
                        .foregroundStyle(DesktopStyle.sidebar)
                        .background(DesktopStyle.text, in: Circle())
                    }
                    .help(viewModel.isPreparing ? "Cancel audio preparation" : viewModel.isPlaying ? "Pause" : "Play")
                    .accessibilityLabel(viewModel.isPreparing ? "Cancel audio preparation" : viewModel.isPlaying ? "Pause" : "Play")
                    .disabled(!viewModel.isModelLoaded || viewModel.sentences.isEmpty || viewModel.isLoading)
                    Button { viewModel.skipForward() } label: {
                        Image(systemName: "goforward.20").font(.system(size: 19)).frame(width: 32, height: 36)
                    }.help("Forward 20 seconds").accessibilityLabel("Forward 20 seconds")
                }
                .buttonStyle(.plain)
                .disabled(viewModel.sentences.isEmpty || viewModel.isLoading)

                Picker("Playback speed", selection: $viewModel.speed) {
                    ForEach(DesktopStyle.speeds, id: \.self) { speed in Text(DesktopStyle.speedLabel(speed)).tag(speed) }
                }
                .labelsHidden().frame(width: 76)
                .help("Playback speed")
                Menu {
                    Button("Restart from beginning", systemImage: "arrow.counterclockwise") { viewModel.restartFromBeginning() }
                        .disabled(!viewModel.isModelLoaded || viewModel.sentences.isEmpty || viewModel.isLoading)
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20)
                .accessibilityLabel("Playback options")
            }
            if queue.isActive {
                HStack {
                    Label("Continuous listening", systemImage: "repeat")
                        .font(.caption).foregroundStyle(DesktopStyle.secondary)
                    Spacer()
                    Button { queue.skip() } label: { Label("Next article", systemImage: "forward.end") }
                        .buttonStyle(.borderless).disabled(viewModel.isLoading)
                    Button { showQueue.toggle() } label: {
                        Label("Up next · \(queue.upcoming.count)", systemImage: "list.bullet")
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showQueue, arrowEdge: .top) {
                        DesktopQueueView(viewModel: viewModel, queue: queue)
                    }
                }
            }
            HStack(spacing: 12) {
                Text("\(Int((seeking ? seekProgress : progress) * 100))%")
                    .frame(width: 34, alignment: .leading)
                Slider(value: Binding(get: { seeking ? seekProgress : progress }, set: { value in
                    seekProgress = value
                    // Keyboard changes do not always enter the dragging lifecycle.
                    if !seeking { seek(to: value) }
                }), in: 0...1, step: 1 / Double(max(viewModel.sentences.count, 1)), onEditingChanged: { editing in
                    if editing { seekProgress = progress; seeking = true }
                    else { seeking = false; seek(to: seekProgress) }
                })
                .controlSize(.small)
                .accessibilityLabel("Article position")
                .accessibilityValue("\(Int((seeking ? seekProgress : progress) * 100)) percent")
                .disabled(viewModel.sentences.isEmpty || viewModel.isLoading)
                Text(remainingTimeLabel)
                    .fixedSize(horizontal: true, vertical: false)
                    .help("Estimated listening time at \(DesktopStyle.speedLabel(viewModel.speed)), based on the remaining text. Updates as sentences advance; actual duration varies by voice and pauses.")
                    .accessibilityLabel("Estimated time remaining")
                    .accessibilityValue(remainingTimeLabel)
            }
            .font(.caption.monospacedDigit()).foregroundStyle(DesktopStyle.secondary)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .background(DesktopStyle.panel)
        .overlay(alignment: .top) { Rectangle().fill(DesktopStyle.border).frame(height: 1) }
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

    private func seek(to value: Double) {
        guard !viewModel.sentences.isEmpty else { return }
        viewModel.seekToSentence(min(viewModel.sentences.count - 1, max(0, Int((value * Double(viewModel.sentences.count)).rounded()))))
    }
}
#endif
