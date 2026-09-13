import Foundation

enum ReaderDocumentSentenceProjector {
    static func segment(
        _ document: ReaderDocument,
        splitProse: (String) -> [String]
    ) -> SegmentedBody {
        var sentences: [String] = []
        var codeBlocks: [Int: CodeBlock] = [:]
        var offsets: [Int] = []
        let plainText = document.plainText as NSString

        for block in document.blocks {
            let range = block.rangeUTF16
            guard range.location >= 0,
                  range.length > 0,
                  range.upperBound <= plainText.length
            else { continue }

            let blockText = plainText.substring(
                with: NSRange(location: range.location, length: range.length)
            )
            if block.kind == .code {
                let codeBlock = CodeBlock(language: nil, source: blockText)
                sentences.append(codeBlock.spokenAnnouncement)
                codeBlocks[sentences.count - 1] = codeBlock
                offsets.append(range.location)
                continue
            }
            guard block.isSpeakable else { continue }

            let segmented = ArticleSegmenter.segment(blockText, splitProse: splitProse)
            sentences.append(contentsOf: segmented.sentences)
            offsets.append(contentsOf: segmented.sentenceStartOffsetsUTF16.map {
                range.location + $0
            })
        }

        return SegmentedBody(
            sentences: sentences,
            codeBlocks: codeBlocks,
            sentenceStartOffsetsUTF16: offsets
        )
    }
}