// Modified for Pagehum: unified application and command-line naming.
import SwiftUI

/// Renders a code block that was lifted out of the spoken stream by `ArticleSegmenter`.
///
/// Playback says only the short announcement ("Swift code block, 12 lines.") — this is where the
/// listener can actually see, scroll and copy the code. Shown in place of `SentenceView` for any
/// index present in `ReaderModel.codeBlocks`.
struct CodeBlockView: View {

    let block: CodeBlock
    let index: Int
    let currentIndex: Int
    let isPlaying: Bool
    var textSize: Double = 17

    /// Tapping the header seeks, matching `SentenceView`'s tap-to-seek. The code area itself is a
    /// horizontal scroll view, so the gesture lives on the header only.
    var onSeek: () -> Void

    @State private var isExpanded = false
    @State private var didCopy = false

    /// Longer blocks start collapsed so a 200-line config dump doesn't bury the article.
    private static let collapsedLineLimit = 12

    private var isCurrent: Bool { index == currentIndex && isPlaying }
    private var isCollapsible: Bool { block.lineCount > Self.collapsedLineLimit }

    private var visibleSource: String {
        guard isCollapsible, !isExpanded else { return block.source }
        return block.source
            .components(separatedBy: "\n")
            .prefix(Self.collapsedLineLimit)
            .joined(separator: "\n")
    }

    private var codeFont: Font {
        .system(size: max(11, CGFloat(textSize) - 2), design: .monospaced)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)
            code
            if isCollapsible { expandToggle }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondaryGroupedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isCurrent ? Color.accentColor.opacity(0.55) : Color.platformGray.opacity(0.22),
                    lineWidth: isCurrent ? 2 : 1
                )
        )
        .padding(.vertical, CGFloat(textSize) * 0.35)
        .animation(.easeInOut(duration: 0.3), value: currentIndex)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isCurrent ? Color.accentColor : .secondary)

            Text(block.displayLanguage ?? "Code")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isCurrent ? Color.accentColor : .secondary)

            Text(block.lineCount == 1 ? "1 line" : "\(block.lineCount) lines")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer(minLength: 8)

            Button(action: copy) {
                Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(didCopy ? Color.green : .secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(didCopy ? "Copied" : "Copy code")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        // Seek lives on the header so it doesn't fight the code area's horizontal scrolling.
        .contentShape(Rectangle())
        .onTapGesture(perform: onSeek)
    }

    // MARK: - Code

    private var code: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Text(visibleSource)
                .font(codeFont)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineSpacing(2)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var expandToggle: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                Text(isExpanded ? "Show less" : "Show all \(block.lineCount) lines")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func copy() {
        #if canImport(UIKit)
        UIPasteboard.general.string = block.source
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(block.source, forType: .string)
        #endif

        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            didCopy = false
        }
    }
}
