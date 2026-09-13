// Modified for Pagehum: unified application and command-line naming.
import Foundation
import Testing
@testable import Pagehum

struct ReaderDocumentProjectionTests {
    @Test
    func pastedTextProducesDeterministicSemanticHTMLAndUTF16BlockProjection() throws {
        let source = "😀 First & <one>\r\nline.\n \nRepeat.\n\nRepeat."
        let firstCreatedAt = Date(timeIntervalSince1970: 1_000)
        let secondCreatedAt = Date(timeIntervalSince1970: 2_000)

        let first = ReaderDocumentBuilder.pastedText(
            title: "Projection fixture",
            text: source,
            createdAt: firstCreatedAt
        )
        let second = ReaderDocumentBuilder.pastedText(
            title: "Projection fixture",
            text: source,
            createdAt: secondCreatedAt
        )

        #expect(first.manifest.schemaVersion == ReaderDocumentManifest.currentSchemaVersion)
        #expect(first.manifest.projectionVersion == ReaderDocumentManifest.currentProjectionVersion)
        #expect(first.manifest.sourceKind == .text)
        #expect(first.manifest.createdAt == firstCreatedAt)
        #expect(first.manifest.projectionRules.blockSeparator == "\n\n")
        #expect(first.plainText == "😀 First & <one>\nline.\n\nRepeat.\n\nRepeat.")
        #expect(first.articleHTML == """
        <article data-pagehum-schema-version="1">
        <p data-pagehum-block-id="block-000001">😀 First &amp; &lt;one&gt;<br>
        line.</p>
        <p data-pagehum-block-id="block-000002">Repeat.</p>
        <p data-pagehum-block-id="block-000003">Repeat.</p>
        </article>
        """)
        #expect(first.blocks.map(\.id) == ["block-000001", "block-000002", "block-000003"])
        #expect(first.blocks.allSatisfy { $0.kind == .prose && $0.isSpeakable })
        #expect(first.articleHTML == second.articleHTML)
        #expect(first.plainText == second.plainText)
        #expect(first.blocks == second.blocks)
        #expect(first.manifest.contentHash == second.manifest.contentHash)

        try first.validateProjection()
        assertRangesTileProjection(first)

        #expect(first.blockIndex.schemaVersion == ReaderDocumentBlockIndex.currentSchemaVersion)
        let encodedBlocks = try JSONEncoder().encode(first.blockIndex)
        let blocksJSON = try #require(String(data: encodedBlocks, encoding: .utf8))
        #expect(!blocksJSON.contains("First"))
        #expect(!blocksJSON.contains("Repeat"))
        #expect(try JSONDecoder().decode(ReaderDocumentBlockIndex.self, from: encodedBlocks) == first.blockIndex)
    }

    @Test
    func sentenceProjectionUsesBlockRangesAndKeepsCodeOutOfSpokenProse() {
        let repeated = "😀 Repeat."
        let code = "let value = 1"
        let document = ReaderDocumentBuilder.webArticle(
            title: "Sentence projection",
            articleHTML: "<article></article>",
            projectedBlocks: [
                ReaderDocumentProjectedBlock(id: "block-000001", kind: .prose, isSpeakable: true, text: repeated),
                ReaderDocumentProjectedBlock(id: "block-000002", kind: .code, isSpeakable: false, text: code),
                ReaderDocumentProjectedBlock(id: "block-000003", kind: .prose, isSpeakable: true, text: repeated),
            ],
            originalURL: URL(string: "https://example.com")!,
            finalURL: URL(string: "https://example.com")!,
            canonicalURL: nil,
            byline: nil,
            siteName: nil,
            excerpt: nil,
            language: nil,
            direction: nil,
            publicationDate: nil
        )

        let segmented = ReaderDocumentSentenceProjector.segment(document) { [$0] }
        let codeOffset = repeated.utf16.count + 2
        let finalProseOffset = codeOffset + code.utf16.count + 2

        #expect(segmented.sentences == [repeated, "Code, one line.", repeated])
        #expect(segmented.sentenceStartOffsetsUTF16 == [0, codeOffset, finalProseOffset])
        #expect(segmented.codeBlocks[1] == CodeBlock(language: nil, source: code))
    }

    private func assertRangesTileProjection(_ document: ReaderDocument) {
        let separator = document.manifest.projectionRules.blockSeparator
        var cursor = 0
        var reconstructed = ""

        for (index, block) in document.blocks.enumerated() {
            if index > 0 {
                let gap = document.plainText.utf16Slice(cursor..<block.rangeUTF16.location)
                #expect(gap == separator)
                reconstructed += gap
            }

            let range = block.rangeUTF16.location..<block.rangeUTF16.upperBound
            let blockText = document.plainText.utf16Slice(range)
            #expect(!blockText.isEmpty)
            reconstructed += blockText
            cursor = block.rangeUTF16.upperBound
        }

        #expect(cursor == document.plainText.utf16.count)
        #expect(reconstructed == document.plainText)
    }
}

private extension String {
    func utf16Slice(_ range: Range<Int>) -> String {
        let start = String.Index(utf16Offset: range.lowerBound, in: self)
        let end = String.Index(utf16Offset: range.upperBound, in: self)
        return String(self[start..<end])
    }
}