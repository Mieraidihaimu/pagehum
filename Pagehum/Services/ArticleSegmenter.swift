// Modified for Pagehum: unified application and command-line naming.
import Foundation

/// The result of splitting an article body into speakable sentences plus the code blocks that were
/// lifted out of it.
///
/// `codeBlocks` is keyed by index into `sentences`: if `codeBlocks[7]` exists, then `sentences[7]`
/// is that block's spoken announcement rather than prose from the article.
struct SegmentedBody {
    let sentences: [String]
    let codeBlocks: [Int: CodeBlock]
    let sentenceStartOffsetsUTF16: [Int]

    static let empty = SegmentedBody(sentences: [], codeBlocks: [:], sentenceStartOffsetsUTF16: [])
}

/// Splits an article body that may carry inline code-block **sentinel markers** into sentences,
/// pulling each code block out of the spoken stream and into a `CodeBlock`.
///
/// ## Why markers rather than a structured body
///
/// `PlaylistItem.fullText` is a plain `String` and resume re-derives sentences from it
/// (`PlaylistView.reloadItem` → `prepareTextPublic`). Encoding code blocks *inside* that string
/// means zero SwiftData migration: articles saved before this feature contain no markers, segment
/// to byte-identical output, and keep their stored `lastSentenceIndex` valid.
///
/// ## Marker format
///
/// ```
/// U+E000  <base64 of {"v":1,"l":"swift","s":"<source>"}>  U+E001
/// ```
///
/// U+E000/U+E001 are Unicode Private Use Area code points — they do not occur in real article text.
/// The payload is base64 so it can never itself contain a delimiter and so newlines are inert.
/// Markers are produced by the reader JS in `TextExtractor`.
///
/// ## Prime directive
///
/// Every malformed input — bad base64, bad JSON, unknown version, unterminated marker, stray
/// delimiter — **degrades to "drop the marker, keep the prose"**. This type never throws, never
/// crashes, and never lets a sentinel character reach spoken text or the screen.
enum ArticleSegmenter {

    private struct SourceSegment {
        let projectedRange: Range<Int>
        let sourceStartUTF16: Int
    }

    // MARK: - Marker format

    static let markerOpen: Character = "\u{E000}"
    static let markerClose: Character = "\u{E001}"

    /// Current payload schema. Bump to invalidate every previously-stored marker.
    static let formatVersion = 1

    /// Hard cap on a single block's stored source. Guards against a pathological page shipping a
    /// megabyte `<pre>`; no real article approaches this.
    static let maxSourceLength = 100_000

    /// The delimiters written as JavaScript string escapes, so the extractor's injected JS and this
    /// parser share one source of truth and cannot drift.
    static var jsMarkerOpen: String { jsEscape(markerOpen) }
    static var jsMarkerClose: String { jsEscape(markerClose) }

    private static func jsEscape(_ character: Character) -> String {
        String(format: "\\u%04X", character.unicodeScalars.first?.value ?? 0)
    }

    // MARK: - Segmenting

    /// Split `text` into sentences, replacing each embedded code-block marker with a single
    /// announcement sentence and recording the block against that sentence's index.
    ///
    /// - Parameters:
    ///   - text: article body, possibly containing markers.
    ///   - splitProse: the prose sentence splitter. Injected rather than owned so this type stays
    ///     pure and off-device testable, and so `ReaderModel.splitIntoSentences` can move to
    ///     `DefaultSentenceSegmenter` later (REFACTOR_PLAN Step 1) without touching this file.
    ///
    /// Marker-free input produces exactly `splitProse(text)` — the pass-through path is the
    /// regression guard for every article saved before this feature existed.
    static func segment(_ text: String, splitProse: (String) -> [String]) -> SegmentedBody {
        guard text.contains(markerOpen) else {
            let projection = sanitizedProjection(text[...], sourceStartUTF16: 0)
            let sentences = splitProse(projection.text)
            return SegmentedBody(
                sentences: sentences,
                codeBlocks: [:],
                sentenceStartOffsetsUTF16: sentenceOffsets(
                    for: sentences,
                    in: projection.text,
                    sourceSegments: projection.sourceSegments
                )
            )
        }

        var sentences: [String] = []
        var codeBlocks: [Int: CodeBlock] = [:]
        var sentenceStartOffsetsUTF16: [Int] = []
        var pendingProse = ""
        var pendingSourceSegments: [SourceSegment] = []

        func sourceOffset(at index: String.Index) -> Int {
            text[..<index].utf16.count
        }

        func appendProse(_ prose: Substring, sourceStartUTF16: Int) {
            guard !prose.isEmpty else { return }
            let projection = sanitizedProjection(prose, sourceStartUTF16: sourceStartUTF16)
            let projectedStart = pendingProse.utf16.count
            pendingProse += projection.text
            pendingSourceSegments.append(contentsOf: projection.sourceSegments.map {
                SourceSegment(
                    projectedRange: ($0.projectedRange.lowerBound + projectedStart)..<($0.projectedRange.upperBound + projectedStart),
                    sourceStartUTF16: $0.sourceStartUTF16
                )
            })
        }

        // Prose is buffered rather than flushed at every marker so that an *undecodable* marker
        // rejoins the text on either side of it into one continuous run.
        func flushProse() {
            guard !pendingProse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                pendingProse = ""
                pendingSourceSegments = []
                return
            }
            let proseSentences = splitProse(pendingProse)
            sentences.append(contentsOf: proseSentences)
            sentenceStartOffsetsUTF16.append(contentsOf: sentenceOffsets(
                for: proseSentences,
                in: pendingProse,
                sourceSegments: pendingSourceSegments
            ))
            pendingProse = ""
            pendingSourceSegments = []
        }

        var cursor = text.startIndex
        while let open = text[cursor...].firstIndex(of: markerOpen) {
            appendProse(text[cursor..<open], sourceStartUTF16: sourceOffset(at: cursor))
            let afterOpen = text.index(after: open)

            guard let close = text[afterOpen...].firstIndex(of: markerClose) else {
                // Unterminated marker: drop the stray delimiter and keep scanning. `cursor` still
                // advances, so this always terminates.
                cursor = afterOpen
                continue
            }

            if let block = decode(String(text[afterOpen..<close])) {
                flushProse()
                sentences.append(block.spokenAnnouncement)
                codeBlocks[sentences.count - 1] = block
                sentenceStartOffsetsUTF16.append(sourceOffset(at: open))
            }
            // An undecodable payload falls through: marker and payload are simply dropped and the
            // surrounding prose stays contiguous in `pendingProse`.

            cursor = text.index(after: close)
        }

        appendProse(text[cursor...], sourceStartUTF16: sourceOffset(at: cursor))
        flushProse()

        return SegmentedBody(
            sentences: sentences,
            codeBlocks: codeBlocks,
            sentenceStartOffsetsUTF16: sentenceStartOffsetsUTF16
        )
    }

    /// `text` with every code-block marker replaced by a single space, for anywhere raw body text is
    /// shown to a human (e.g. `PlaylistItem.textPreview`).
    static func strippingMarkers(_ text: String) -> String {
        guard text.contains(markerOpen) || text.contains(markerClose) else { return text }

        var out = ""
        var cursor = text.startIndex
        while let open = text[cursor...].firstIndex(of: markerOpen) {
            out += text[cursor..<open]
            let afterOpen = text.index(after: open)
            guard let close = text[afterOpen...].firstIndex(of: markerClose) else {
                cursor = afterOpen
                continue
            }
            out += " "
            cursor = text.index(after: close)
        }
        out += text[cursor...]
        return sanitized(out)
    }

    /// Build a marker for `block`. The reader JS is the production producer; this exists so the
    /// format is expressible (and testable) from Swift too.
    static func marker(for block: CodeBlock) -> String {
        let payload = MarkerPayload(v: formatVersion, l: block.language, s: block.source)
        guard let data = try? JSONEncoder().encode(payload) else { return "" }
        return String(markerOpen) + data.base64EncodedString() + String(markerClose)
    }

    // MARK: - Private

    private static func sanitizedProjection(
        _ source: Substring,
        sourceStartUTF16: Int
    ) -> (text: String, sourceSegments: [SourceSegment]) {
        var text = ""
        var sourceSegments: [SourceSegment] = []
        var cursor = source.startIndex

        func append(_ chunk: Substring) {
            guard !chunk.isEmpty else { return }
            let projectedStart = text.utf16.count
            text += chunk
            sourceSegments.append(SourceSegment(
                projectedRange: projectedStart..<text.utf16.count,
                sourceStartUTF16: sourceStartUTF16 + source[..<chunk.startIndex].utf16.count
            ))
        }

        while let delimiter = source[cursor...].firstIndex(where: {
            $0 == markerOpen || $0 == markerClose
        }) {
            append(source[cursor..<delimiter])
            cursor = source.index(after: delimiter)
        }
        append(source[cursor...])

        return (text, sourceSegments)
    }

    private static func sentenceOffsets(
        for sentences: [String],
        in prose: String,
        sourceSegments: [SourceSegment]
    ) -> [Int] {
        var searchStart = prose.startIndex

        return sentences.map { sentence in
            let searchRange = searchStart..<prose.endIndex
            let match = prose.range(of: sentence, range: searchRange) ?? prose.range(of: sentence)
            guard let match else {
                return sourceSegments.first?.sourceStartUTF16 ?? 0
            }

            searchStart = match.upperBound
            let projectedOffset = prose[..<match.lowerBound].utf16.count
            guard let sourceSegment = sourceSegments.first(where: {
                $0.projectedRange.contains(projectedOffset)
            }) else {
                return sourceSegments.last?.sourceStartUTF16 ?? projectedOffset
            }

            return sourceSegment.sourceStartUTF16
                + projectedOffset
                - sourceSegment.projectedRange.lowerBound
        }
    }

    private struct MarkerPayload: Codable {
        let v: Int
        let l: String?
        let s: String
    }

    private static func decode(_ payload: String) -> CodeBlock? {
        guard let data = Data(base64Encoded: payload),
              let decoded = try? JSONDecoder().decode(MarkerPayload.self, from: data),
              decoded.v == formatVersion
        else { return nil }

        // Trim only newlines, so leading indentation on the first content line survives.
        var source = decoded.s.trimmingCharacters(in: .newlines)
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if source.count > maxSourceLength { source = String(source.prefix(maxSourceLength)) }

        let language = decoded.l?.lowercased().trimmingCharacters(in: .whitespaces)
        return CodeBlock(language: (language?.isEmpty == false) ? language : nil, source: source)
    }

    /// Belt-and-braces removal of any delimiter that survived parsing (e.g. a stray close with no
    /// open). Guarantees no sentinel ever reaches TTS or the screen.
    private static func sanitized(_ text: String) -> String {
        guard text.contains(markerOpen) || text.contains(markerClose) else { return text }
        return text.filter { $0 != markerOpen && $0 != markerClose }
    }
}
