// Modified for Pagehum: unified application and command-line naming.
import Testing
@testable import Pagehum

struct ArticleSegmenterOffsetTests {
    @Test
    func preservesUTF16SourceOffsetsAcrossCodeMarkersAndRepeatedProse() {
        let prose = "😀 Repeat me."
        let marker = ArticleSegmenter.marker(for: CodeBlock(language: "swift", source: "let value = 1"))
        let body = "\(prose)\n\n\(marker)\n\n\(prose)"

        let segmented = ArticleSegmenter.segment(body) { text in
            text.split(whereSeparator: \.isNewline).map(String.init)
        }

        let markerOffset = prose.utf16.count + 2
        #expect(segmented.sentences == [prose, "Swift code, one line.", prose])
        #expect(segmented.sentenceStartOffsetsUTF16 == [
            0,
            markerOffset,
            markerOffset + marker.utf16.count + 2,
        ])
    }

    @Test
    func preservesSourceOffsetAfterStrayClosingMarker() {
        let body = "First.\(ArticleSegmenter.markerClose) Second."

        let segmented = ArticleSegmenter.segment(body) { text in
            text.split(separator: " ").map(String.init)
        }

        #expect(segmented.sentences == ["First.", "Second."])
        #expect(segmented.sentenceStartOffsetsUTF16 == [0, 8])
    }

    @Test
    func preservesSourceOffsetAfterUnterminatedOpeningMarker() {
        let body = "First.\(ArticleSegmenter.markerOpen) Second."

        let segmented = ArticleSegmenter.segment(body) { text in
            text.split(separator: " ").map(String.init)
        }

        #expect(segmented.sentences == ["First.", "Second."])
        #expect(segmented.sentenceStartOffsetsUTF16 == [0, 8])
    }

    @Test
    func dropsInvalidPairedMarkerWithoutCollapsingLaterSourceOffset() {
        let malformed = "\(ArticleSegmenter.markerOpen)not-base64\(ArticleSegmenter.markerClose)"
        let body = "First.\(malformed) Second."

        let segmented = ArticleSegmenter.segment(body) { text in
            text.split(separator: " ").map(String.init)
        }

        #expect(segmented.sentences == ["First.", "Second."])
        #expect(segmented.sentenceStartOffsetsUTF16 == [0, 7 + malformed.utf16.count])
    }
}