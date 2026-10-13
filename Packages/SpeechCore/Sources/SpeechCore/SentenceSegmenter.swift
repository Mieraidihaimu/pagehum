import Foundation
import NaturalLanguage

public enum SentenceSegmenter {
    private static let maxSentenceLength = 400

    public static func splitIntoSentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let s = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty {
                if s.count <= maxSentenceLength {
                    result.append(s)
                } else {
                    result.append(contentsOf: splitLongSentence(s))
                }
            }
            return true
        }
        if result.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result = text.count <= maxSentenceLength ? [text] : splitLongSentence(text)
        }
        return result
    }

    private static func splitLongSentence(_ sentence: String) -> [String] {
        let delimiters: [Character] = [",", ";", ":", "—", "–"]
        var chunks: [String] = []
        var current = ""

        for char in sentence {
            current.append(char)
            if delimiters.contains(char) && current.count >= 80 {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { chunks.append(trimmed) }
                current = ""
            }
        }
        let remaining = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty { chunks.append(remaining) }

        // If we couldn't split effectively, split at word boundaries
        if chunks.count <= 1 && sentence.count > maxSentenceLength {
            chunks = []
            let words = sentence.split(separator: " ")
            current = ""
            for word in words {
                if current.count + word.count + 1 > maxSentenceLength && !current.isEmpty {
                    chunks.append(current)
                    current = String(word)
                } else {
                    current += (current.isEmpty ? "" : " ") + word
                }
            }
            if !current.isEmpty { chunks.append(current) }
        }

        // A clause or a single word may itself exceed Kokoro's input budget.
        // Bound every result, including clauses in otherwise splittable sentences.
        return (chunks.isEmpty ? [sentence] : chunks).flatMap { chunk -> [String] in
            var remaining = chunk[...]
            var bounded: [String] = []
            while remaining.count > maxSentenceLength {
                let limit = remaining.index(remaining.startIndex, offsetBy: maxSentenceLength)
                let prefix = remaining[..<limit]
                let boundary = prefix.lastIndex(where: { $0.isWhitespace }) ?? limit
                let end = boundary == remaining.startIndex ? limit : boundary
                let part = String(remaining[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !part.isEmpty { bounded.append(part) }
                remaining = remaining[end...].drop(while: { $0.isWhitespace })
            }
            let tail = String(remaining).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { bounded.append(tail) }
            return bounded
        }
    }
}
