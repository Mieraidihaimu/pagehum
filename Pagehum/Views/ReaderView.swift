// Modified for Pagehum: unified application and command-line naming.
import SwiftUI

struct ReaderView: View {

    @ObservedObject var viewModel: ReaderModel
    var showsPlaybackControls = true
    var desktopLayout = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    var body: some View {
        Group {
            if viewModel.content != nil {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if desktopLayout {
                                VStack(alignment: .leading, spacing: 16) {
                                    if let site = viewModel.content?.siteName {
                                        Text(site.uppercased()).font(.caption).tracking(1.6).foregroundStyle(.secondary)
                                    }
                                    Text(viewModel.content?.title ?? "Reader")
                                        .font(.largeTitle.weight(.medium)).tracking(-0.8)
                                        .accessibilityAddTraits(.isHeader)
                                }
                                .padding(.bottom, 20)
                            }
                            if let byline = viewModel.content?.byline, !byline.isEmpty {
                                HStack(spacing: 4) {
                                    if let site = viewModel.content?.siteName, !site.isEmpty {
                                        Text(byline)
                                            .font(.subheadline.weight(.medium))
                                        Text("·")
                                        Text(site)
                                            .font(.subheadline)
                                    } else {
                                        Text(byline)
                                            .font(.subheadline.weight(.medium))
                                    }
                                }
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 12)
                            }
                            ForEach(Array(viewModel.sentences.enumerated()), id: \.offset) { index, sentence in
                                // Code blocks occupy a sentence slot but render as a code card —
                                // playback only speaks their announcement. See ArticleSegmenter.
                                if let block = viewModel.codeBlock(at: index) {
                                    CodeBlockView(
                                        block: block,
                                        index: index,
                                        currentIndex: viewModel.currentSentenceIndex,
                                        isPlaying: viewModel.isPlaying,
                                        textSize: viewModel.textSize,
                                        onSeek: { viewModel.seekToSentence(index) }
                                    )
                                    .id(index)
                                } else {
                                    Button { viewModel.seekToSentence(index) } label: {
                                        SentenceView(
                                            sentence: sentence,
                                            index: index,
                                            currentIndex: viewModel.currentSentenceIndex,
                                            isPlaying: viewModel.isPlaying,
                                            currentWord: index == viewModel.currentSentenceIndex ? viewModel.currentWordText : "",
                                            currentTokenIndex: index == viewModel.currentSentenceIndex ? viewModel.currentTokenIndex : -1,
                                            textSize: viewModel.textSize
                                        )
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(sentence)
                                    .accessibilityValue(index == viewModel.currentSentenceIndex ? "Current sentence" : "")
                                    .accessibilityHint("Moves playback to this sentence.")
                                    .id(index)
                                }
                            }
                        }
                        .frame(maxWidth: desktopLayout ? 620 : .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, desktopLayout ? 40 : 20)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity)
                    }
                    .background(Color.platformGroupedBackground.opacity(0.5))
                    .onAppear {
                        if !voiceOverEnabled && viewModel.currentSentenceIndex > 0 {
                            proxy.scrollTo(viewModel.currentSentenceIndex, anchor: .center)
                        }
                    }
                    .onChange(of: viewModel.currentSentenceIndex) { _, newIndex in
                        // Keep VoiceOver's reading position under the listener's control.
                        guard !voiceOverEnabled else { return }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if showsPlaybackControls, viewModel.content != nil {
                PlaybackControlsView(viewModel: viewModel)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
        }
        .navigationTitle(viewModel.content?.title ?? "Reader")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        #endif
    }
}

// MARK: - Sentence

struct SentenceView: View {
    let sentence: String
    let index: Int
    let currentIndex: Int
    let isPlaying: Bool
    let currentWord: String
    let currentTokenIndex: Int
    var textSize: Double = 17
    @ScaledMetric(relativeTo: .body) private var textScale = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var scaledTextSize: CGFloat { CGFloat(textSize * textScale) }

    private var readerFont: Font {
        .system(size: scaledTextSize, design: .serif)
    }

    private var lineSpacing: CGFloat { scaledTextSize * 0.5 }

    var body: some View {
        Group {
            if index == currentIndex && isPlaying && !currentWord.isEmpty {
                highlightedSentence
            } else {
                Text(sentence)
                    .font(readerFont)
                    .foregroundStyle(textColor)
            }
        }
        .lineSpacing(lineSpacing)
        .padding(.vertical, scaledTextSize * 0.35)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrent ? Color.accentColor.opacity(0.06) : .clear)
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: currentIndex)
    }

    private var isCurrent: Bool { index == currentIndex && isPlaying }

    private var textColor: Color {
        if !isPlaying || contrast == .increased { return .primary }
        if index == currentIndex { return .primary }
        if index < currentIndex { return .secondary }
        return .primary.opacity(0.8)
    }

    private var highlightedSentence: some View {
        let words = sentence.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let target = currentWord.trimmingCharacters(in: .punctuationCharacters).lowercased()
        let activeWordIndex = findActiveWordIndex(words: words, target: target, tokenIndex: currentTokenIndex)

        return words.enumerated().reduce(Text("")) { result, pair in
            let (wordIdx, word) = pair
            let isActive = wordIdx == activeWordIndex
            let styledWord = Text(word + " ")
                .foregroundColor(isActive ? .accentColor : .primary)
                .fontWeight(isActive ? .semibold : .regular)
                .underline(isActive, color: .accentColor.opacity(0.5))
            return result + styledWord
        }
        .font(readerFont)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func findActiveWordIndex(words: [String], target: String, tokenIndex: Int) -> Int? {
        guard !target.isEmpty else { return nil }

        // TTS tokens may not map 1:1 to whitespace-split words (punctuation-only
        // tokens get skipped in the display). Use tokenIndex as a starting hint
        // and search outward for the matching word.
        let searchStart = min(tokenIndex, words.count - 1)
        let searchRange = max(0, searchStart - 2)...min(words.count - 1, searchStart + 2)

        for i in searchRange {
            let stripped = words[i].trimmingCharacters(in: .punctuationCharacters).lowercased()
            if stripped == target { return i }
        }

        // Broader fallback: exact match only, first occurrence at or after tokenIndex
        for i in max(0, tokenIndex)..<words.count {
            let stripped = words[i].trimmingCharacters(in: .punctuationCharacters).lowercased()
            if stripped == target { return i }
        }
        return nil
    }
}
