// Modified for Pagehum: unified application and command-line naming.
import Foundation

/// A structured table lifted out of an article body for semantic audio reading and styled display.
///
/// Like `CodeBlock`, a table occupies one index slot in `ReaderModel.sentences` — the slot holds
/// `spokenAnnouncement` ("Table, 3 columns and 4 rows.") while the formatted table structure lives
/// here, in the parallel `ReaderModel.tableBlocks` map.
public struct TableBlock: Codable, Equatable, Hashable, Sendable {

    public let headers: [String]
    public let rows: [[String]]
    public let caption: String?
    public let rawText: String

    public init(headers: [String] = [], rows: [[String]] = [], caption: String? = nil, rawText: String = "") {
        self.headers = headers
        self.rows = rows
        self.caption = caption
        self.rawText = rawText
    }

    /// Construct a `TableBlock` from tab- and newline-delimited text projected by `ReaderWebDocumentExtractor`.
    public init(rawText: String, caption: String? = nil) {
        self.rawText = rawText
        self.caption = caption
        let lines = rawText
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var parsedRows: [[String]] = []
        for line in lines {
            let cells = line
                .components(separatedBy: "\t")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if !cells.allSatisfy(\.isEmpty) {
                parsedRows.append(cells)
            }
        }

        if let first = parsedRows.first, parsedRows.count > 1 {
            self.headers = first
            self.rows = Array(parsedRows.dropFirst())
        } else {
            self.headers = []
            self.rows = parsedRows
        }
    }

    public var columnCount: Int {
        max(headers.count, rows.map(\.count).max() ?? 0)
    }

    public var rowCount: Int {
        rows.count + (headers.isEmpty ? 0 : 1)
    }

    /// Short, natural announcement spoken by Kokoro in place of reading raw cell contents.
    public var spokenAnnouncement: String {
        let cols = columnCount == 1 ? "one column" : "\(columnCount) columns"
        let rws = rowCount == 1 ? "one row" : "\(rowCount) rows"
        if let caption, !caption.isEmpty {
            return "Table with \(cols) and \(rws), \(caption)."
        }
        return "Table, \(cols) and \(rws)."
    }

    /// Comma-separated full content spoken in `.verbatim` mode.
    public var verbatimText: String {
        var lines: [String] = []
        if let caption, !caption.isEmpty {
            lines.append(caption)
        }
        if !headers.isEmpty {
            lines.append("Headers: " + headers.joined(separator: ", "))
        }
        for (i, row) in rows.enumerated() {
            let rowText = row.filter { !$0.isEmpty }.joined(separator: ", ")
            if !rowText.isEmpty {
                lines.append("Row \(i + 1): " + rowText)
            }
        }
        return lines.joined(separator: ". ")
    }

    /// Short needle from the table used for DOM search / highlighting in `WebReaderView`.
    public var firstSubstantialCell: String? {
        if let caption, caption.count >= 6 { return caption }
        for cell in headers where cell.count >= 4 { return cell }
        for row in rows {
            for cell in row where cell.count >= 4 { return cell }
        }
        return headers.first ?? rows.first?.first
    }
}
