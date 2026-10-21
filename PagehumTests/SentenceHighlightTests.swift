import Testing
@testable import Pagehum

struct SentenceHighlightTests {
    @Test(arguments: [-1, 0, 2, 3, 100, Int.min, Int.max])
    func unmatchedTokensNeverCreateAnInvalidSearchRange(tokenIndex: Int) {
        #expect(SentenceView.findActiveWordIndex(
            words: ["A", "short", "sentence."], target: "unmatched", tokenIndex: tokenIndex
        ) == nil)
    }

    @Test
    func emptySentencesAndTargetsHaveNoHighlight() {
        #expect(SentenceView.findActiveWordIndex(words: [], target: "word", tokenIndex: 4) == nil)
        #expect(SentenceView.findActiveWordIndex(words: ["word"], target: "", tokenIndex: 0) == nil)
    }

    @Test
    func matchesNearbyWordsWhenSpeechAndWhitespaceTokenCountsDiffer() {
        #expect(SentenceView.findActiveWordIndex(
            words: ["Well-known", "words", "repeat", "words."], target: "words", tokenIndex: 5
        ) == 1)
        #expect(SentenceView.findActiveWordIndex(
            words: ["Hello,"], target: "hello", tokenIndex: -1
        ) == 0)
    }
}
