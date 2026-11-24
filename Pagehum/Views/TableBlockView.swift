// Modified for Pagehum: unified application and command-line naming.
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Renders a structured table lifted out of the spoken stream by `ReaderDocumentSentenceProjector`.
///
/// Playback speaks a clean summary ("Table, 3 columns and 4 rows.") — this view lets the reader
/// view, scroll, expand, and copy the tabular content. Shown in place of `SentenceView` for any
/// index present in `ReaderModel.tableBlocks`.
struct TableBlockView: View {

    let block: TableBlock
    let index: Int
    let currentIndex: Int
    let isPlaying: Bool
    var textSize: Double = 17
    var onSeek: () -> Void

    @State private var isExpanded = false
    @State private var didCopy = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let collapsedRowLimit = 5

    private var isCurrent: Bool { index == currentIndex && isPlaying }
    private var isCollapsible: Bool { block.rows.count > Self.collapsedRowLimit }

    private var visibleRows: [[String]] {
        guard isCollapsible, !isExpanded else { return block.rows }
        return Array(block.rows.prefix(Self.collapsedRowLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)
            tableContent
            if isCollapsible {
                expandToggle
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.surface)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isCurrent ? AppTheme.borderFocus : AppTheme.borderSubtle,
                    lineWidth: isCurrent ? 2 : 1
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [AppTheme.darkTopHighlight, .clear],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: AppTheme.cardShadow, radius: 12, x: 0, y: 4)
        .padding(.vertical, CGFloat(textSize) * 0.35)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: currentIndex)
    }

    private var header: some View {
        HStack {
            Button(action: onSeek) {
                HStack(spacing: 8) {
                    Image(systemName: "tablecells")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isCurrent ? AppTheme.accentPrimary : AppTheme.textSecondary)
                    Text("Table")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isCurrent ? AppTheme.accentPrimary : AppTheme.textPrimary)
                    Text("· \(block.columnCount) × \(block.rowCount)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    if let caption = block.caption, !caption.isEmpty {
                        Text("· \(caption)")
                            .font(.caption.italic())
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: copyTable) {
                HStack(spacing: 4) {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                    Text(didCopy ? "Copied" : "Copy")
                        .font(.caption2)
                }
                .foregroundStyle(didCopy ? AppTheme.success : AppTheme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppTheme.elevated)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var tableContent: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                if !block.headers.isEmpty {
                    rowView(cells: block.headers, isHeader: true)
                    Divider().opacity(0.6)
                }
                ForEach(Array(visibleRows.enumerated()), id: \.offset) { rowIndex, row in
                    rowView(cells: row, isHeader: false)
                    if rowIndex < visibleRows.count - 1 {
                        Divider().opacity(0.25)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func rowView(cells: [String], isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(cell)
                    .font(.system(size: max(11, CGFloat(textSize) - 2), weight: isHeader ? .semibold : .regular))
                    .foregroundStyle(isHeader ? AppTheme.textPrimary : AppTheme.textSecondary)
                    .frame(minWidth: 70, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }

    private var expandToggle: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                Text(isExpanded ? "Show fewer rows" : "Show all \(block.rowCount) rows")
                    .font(.caption)
            }
            .foregroundStyle(AppTheme.accentText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(AppTheme.elevated.opacity(0.6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func copyTable() {
        #if canImport(UIKit)
        UIPasteboard.general.string = block.rawText
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(block.rawText, forType: .string)
        #endif
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            didCopy = false
        }
    }
}
