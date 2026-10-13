// Modified for Pagehum: unified application and command-line naming.
import XCTest
import SpeechCore
@testable import Pagehum

final class SentenceSegmenterTests: XCTestCase {
    func testBoundsEveryClauseWithoutDroppingWords() {
        let text = String(repeating: "hello ", count: 100) + ", " + String(repeating: "world ", count: 100)
        let chunks = SentenceSegmenter.splitIntoSentences(text)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 400 })
        XCTAssertEqual(chunks.joined().filter { !$0.isWhitespace }, text.filter { !$0.isWhitespace })
    }

    func testBoundsLongUnbrokenInput() {
        let text = String(repeating: "a", count: 1201)
        let chunks = SentenceSegmenter.splitIntoSentences(text)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 400 })
        XCTAssertEqual(chunks.joined(), text)
    }

    func testEmptyInputAndOrdinarySentences() {
        XCTAssertEqual(SentenceSegmenter.splitIntoSentences(" \n\t"), [])
        XCTAssertEqual(SentenceSegmenter.splitIntoSentences("Hello there. How are you?"), ["Hello there.", "How are you?"])
    }
}
