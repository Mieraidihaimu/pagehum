import Foundation

enum ReaderDocumentSentenceProjector {
    static func segment(
        _ document: ReaderDocument,
        mode: AudioCleanMode = .clean,
        splitProse: (String) -> [String]
    ) -> SegmentedBody {
        var sentences: [String] = []
        var codeBlocks: [Int: CodeBlock] = [:]
        var tableBlocks: [Int: TableBlock] = [:]
        var spokenTextMappings: [Int: SpokenTextMapping] = [:]
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
                let spokenText: String
                switch mode {
                case .clean, .muted:
                    spokenText = codeBlock.spokenAnnouncement
                case .verbatim:
                    spokenText = codeBlock.source
                }
                sentences.append(spokenText)
                let slotIndex = sentences.count - 1
                codeBlocks[slotIndex] = codeBlock
                offsets.append(range.location)
                continue
            }

            if block.kind == .table {
                let tableBlock = TableBlock(rawText: blockText)
                let spokenText: String
                switch mode {
                case .clean, .muted:
                    spokenText = tableBlock.spokenAnnouncement
                case .verbatim:
                    spokenText = tableBlock.verbatimText.isEmpty ? tableBlock.spokenAnnouncement : tableBlock.verbatimText
                }
                sentences.append(spokenText)
                let slotIndex = sentences.count - 1
                tableBlocks[slotIndex] = tableBlock
                offsets.append(range.location)
                continue
            }

            guard block.isSpeakable else { continue }

            let segmented = ArticleSegmenter.segment(blockText, splitProse: splitProse)
            let baseIndex = sentences.count
            sentences.append(contentsOf: segmented.sentences)

            for (innerIndex, block) in segmented.codeBlocks {
                codeBlocks[baseIndex + innerIndex] = block
            }
            for (innerIndex, block) in segmented.tableBlocks {
                tableBlocks[baseIndex + innerIndex] = block
            }

            for (innerIndex, sentence) in segmented.sentences.enumerated() {
                let globalIndex = baseIndex + innerIndex
                if codeBlocks[globalIndex] == nil && tableBlocks[globalIndex] == nil {
                    if mode != .verbatim {
                        let mapping = AudioCleanFilter.cleanForSpeech(sentence)
                        if !mapping.shifts.isEmpty {
                            spokenTextMappings[globalIndex] = mapping
                        }
                    }
                }
            }

            offsets.append(contentsOf: segmented.sentenceStartOffsetsUTF16.map {
                range.location + $0
            })
        }

        return SegmentedBody(
            sentences: sentences,
            codeBlocks: codeBlocks,
            tableBlocks: tableBlocks,
            spokenTextMappings: spokenTextMappings,
            sentenceStartOffsetsUTF16: offsets
        )
    }
}
