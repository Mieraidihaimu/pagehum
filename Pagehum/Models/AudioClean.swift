// Modified for Pagehum: unified application and command-line naming.
import Foundation

/// User preference mode controlling how non-prose and auxiliary elements are spoken.
public enum AudioCleanMode: String, Codable, CaseIterable, Sendable {
    /// Recommended: clean announcements for code and tables; strips in-text footnote citations.
    case clean = "clean"
    /// Reads raw code, table cells, and citations verbatim.
    case verbatim = "verbatim"
    /// Silently skips code and tables; strips in-text citations.
    case muted = "muted"

    public var title: String {
        switch self {
        case .clean: "Audio-Clean"
        case .verbatim: "Verbatim"
        case .muted: "Mute Non-Prose"
        }
    }

    public var description: String {
        switch self {
        case .clean: "Announce code and tables; filter footnote numbers."
        case .verbatim: "Speak raw code, table cells, and footnote citations."
        case .muted: "Silently skip code blocks, tables, and footnote citations."
        }
    }
}

/// A recorded UTF-16 offset shift resulting from stripping text (e.g. citations) for speech.
public struct OffsetShift: Codable, Equatable, Hashable, Sendable {
    /// The UTF-16 code unit offset in `spokenText` where text was removed.
    public let spokenOffset: Int
    /// Number of UTF-16 code units removed from `displayText`.
    public let removedLength: Int

    public init(spokenOffset: Int, removedLength: Int) {
        self.spokenOffset = spokenOffset
        self.removedLength = removedLength
    }
}

/// Couples a visible display sentence with its synthesized spoken counterpart and an offset map.
public struct SpokenTextMapping: Codable, Equatable, Hashable, Sendable {
    /// The original sentence with full punctuation and visible citations intact.
    public let displayText: String
    /// The cleaned text sent to the Kokoro speech synthesis engine.
    public let spokenText: String
    /// Shifts sorted in ascending order of `spokenOffset`.
    public let shifts: [OffsetShift]

    public init(displayText: String, spokenText: String, shifts: [OffsetShift] = []) {
        self.displayText = displayText
        self.spokenText = spokenText
        self.shifts = shifts
    }

    public static func identity(_ text: String) -> SpokenTextMapping {
        SpokenTextMapping(displayText: text, spokenText: text, shifts: [])
    }

    /// Maps an NSRange from `spokenText` (e.g. from Kokoro token timestamps) back to `displayText`.
    public func displayRange(forSpokenRange spokenRange: NSRange) -> NSRange {
        guard !shifts.isEmpty, spokenRange.location != NSNotFound else { return spokenRange }

        var startDelta = 0
        var internalDelta = 0
        let spokenEnd = spokenRange.location + spokenRange.length

        for shift in shifts {
            if shift.spokenOffset <= spokenRange.location {
                startDelta += shift.removedLength
            } else if shift.spokenOffset < spokenEnd {
                internalDelta += shift.removedLength
            } else {
                break
            }
        }

        return NSRange(
            location: spokenRange.location + startDelta,
            length: spokenRange.length + internalDelta
        )
    }
}

/// High-performance filter that strips in-text citations and non-speakable artifacts from prose.
public enum AudioCleanFilter {

    /// Matches bracketed citation patterns such as [1], [24], [1, 2], [1-3], [note 1], [citation needed].
    /// Requires positive citation numbers starting with 1-9 to avoid matching array[0] or interval [0, 1].
    /// Also consumes preceding whitespace if followed by punctuation so that `"word [1]."` becomes `"word."`.
    private static let citationRegex: NSRegularExpression = {
        let pattern = #"(?:[ \t]+)?\[\s*(?:[1-9]\d{0,3}(?:\s*[,–—-]\s*[1-9]\d{0,3})*|note\s*\d+|citation\s+needed|source|ref)\s*\](?=[.,;!?]|\s|$)"#
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    /// Matches standalone superscript Unicode numbers (e.g. ¹, ², ³, etc.).
    private static let superscriptRegex: NSRegularExpression = {
        let pattern = #"(?:[ \t]+)?[¹²³⁴⁵⁶⁷⁸⁹⁰]+(?=[.,;!?]|\s|$)"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    /// Clean a sentence for speech synthesis while recording the character offset shifts.
    public static func cleanForSpeech(_ displayText: String) -> SpokenTextMapping {
        guard !displayText.isEmpty else { return .identity(displayText) }

        let nsString = displayText as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)

        // Find citation matches
        var matchRanges: [NSRange] = []
        citationRegex.enumerateMatches(in: displayText, options: [], range: fullRange) { match, _, _ in
            if let range = match?.range {
                matchRanges.append(range)
            }
        }
        superscriptRegex.enumerateMatches(in: displayText, options: [], range: fullRange) { match, _, _ in
            if let range = match?.range {
                matchRanges.append(range)
            }
        }

        guard !matchRanges.isEmpty else {
            return .identity(displayText)
        }

        // Sort match ranges and remove any overlaps
        matchRanges.sort { $0.location < $1.location }
        var nonOverlapping: [NSRange] = []
        for r in matchRanges {
            if let last = nonOverlapping.last, r.location < last.location + last.length {
                continue
            }
            nonOverlapping.append(r)
        }

        // Exclude programming indexing like `array[1]` where bracket is directly attached to an identifier without space
        var validMatches: [NSRange] = []
        for r in nonOverlapping {
            let matchedText = nsString.substring(with: r)
            let isBracketCitation = matchedText.contains("[")
            let hasLeadingWhitespace = matchedText.first == " " || matchedText.first == "\t"
            if isBracketCitation && !hasLeadingWhitespace && r.location > 0 {
                let prevChar = nsString.character(at: r.location - 1)
                if let scalar = UnicodeScalar(prevChar), CharacterSet.alphanumerics.contains(scalar) {
                    continue
                }
            }
            validMatches.append(r)
        }

        guard !validMatches.isEmpty else {
            return .identity(displayText)
        }

        var spokenText = ""
        var shifts: [OffsetShift] = []
        var cursor = 0

        for match in validMatches {
            if match.location > cursor {
                let segment = nsString.substring(with: NSRange(location: cursor, length: match.location - cursor))
                spokenText += segment
            }
            let currentSpokenOffset = (spokenText as NSString).length
            shifts.append(OffsetShift(spokenOffset: currentSpokenOffset, removedLength: match.length))
            cursor = match.location + match.length
        }

        if cursor < nsString.length {
            let tail = nsString.substring(with: NSRange(location: cursor, length: nsString.length - cursor))
            spokenText += tail
        }

        // Clean up any stray double spaces
        let trimmedSpoken = spokenText.replacingOccurrences(of: "  ", with: " ")
        return SpokenTextMapping(displayText: displayText, spokenText: trimmedSpoken, shifts: shifts)
    }
}
