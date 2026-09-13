// Modified for Pagehum: unified application and command-line naming.
import CryptoKit
import Foundation

struct ReaderDocumentProjectedBlock {
    let id: String
    let kind: ReaderDocumentBlock.Kind
    let isSpeakable: Bool
    let text: String
}

enum ReaderDocumentBuilder {
    private static let blockSeparator = "\n\n"
    private static let blankLinePattern = try! NSRegularExpression(pattern: "\n(?:[ \\t]*\n)+")

    static func pastedText(
        title: String,
        text sourceText: String,
        createdAt: Date = Date()
    ) -> ReaderDocument {
        let paragraphTexts = paragraphs(in: sourceText)
        var htmlBlocks: [String] = []
        var projectedBlocks: [ReaderDocumentProjectedBlock] = []

        for (index, paragraph) in paragraphTexts.enumerated() {
            let blockID = String(format: "block-%06d", index + 1)
            projectedBlocks.append(ReaderDocumentProjectedBlock(
                id: blockID,
                kind: .prose,
                isSpeakable: true,
                text: paragraph
            ))
            htmlBlocks.append(
                "<p data-pagehum-block-id=\"\(blockID)\">\(htmlText(paragraph))</p>"
            )
        }

        let articleHTML = ([
            "<article data-pagehum-schema-version=\"\(ReaderDocumentManifest.currentSchemaVersion)\">",
        ] + htmlBlocks + ["</article>"]).joined(separator: "\n")

        return build(
            sourceKind: .text,
            title: title,
            articleHTML: articleHTML,
            projectedBlocks: projectedBlocks,
            createdAt: createdAt
        )
    }

    static func webArticle(
        title: String,
        articleHTML: String,
        projectedBlocks: [ReaderDocumentProjectedBlock],
        originalURL: URL,
        finalURL: URL,
        canonicalURL: URL?,
        byline: String?,
        siteName: String?,
        excerpt: String?,
        language: String?,
        direction: String?,
        publicationDate: String?,
        createdAt: Date = Date()
    ) -> ReaderDocument {
        build(
            sourceKind: .url,
            title: title,
            articleHTML: articleHTML,
            projectedBlocks: projectedBlocks,
            createdAt: createdAt,
            originalURL: originalURL,
            finalURL: finalURL,
            canonicalURL: canonicalURL,
            byline: byline,
            siteName: siteName,
            excerpt: excerpt,
            language: language,
            direction: direction,
            publicationDate: publicationDate
        )
    }

    private static func build(
        sourceKind: ReaderDocumentManifest.SourceKind,
        title: String,
        articleHTML: String,
        projectedBlocks: [ReaderDocumentProjectedBlock],
        createdAt: Date,
        originalURL: URL? = nil,
        finalURL: URL? = nil,
        canonicalURL: URL? = nil,
        byline: String? = nil,
        siteName: String? = nil,
        excerpt: String? = nil,
        language: String? = nil,
        direction: String? = nil,
        publicationDate: String? = nil
    ) -> ReaderDocument {
        var plainText = ""
        var blocks: [ReaderDocumentBlock] = []

        for (index, projectedBlock) in projectedBlocks.enumerated() {
            if index > 0 { plainText += blockSeparator }
            let location = plainText.utf16.count
            plainText += projectedBlock.text
            blocks.append(ReaderDocumentBlock(
                id: projectedBlock.id,
                kind: projectedBlock.kind,
                isSpeakable: projectedBlock.isSpeakable,
                rangeUTF16: ReaderDocumentUTF16Range(
                    location: location,
                    length: projectedBlock.text.utf16.count
                )
            ))
        }

        let contentHash = SHA256.hash(
            data: Data((articleHTML + "\u{0}" + plainText).utf8)
        ).map { String(format: "%02x", $0) }.joined()

        return ReaderDocument(
            manifest: ReaderDocumentManifest(
                sourceKind: sourceKind,
                title: title,
                createdAt: createdAt,
                contentHash: contentHash,
                projectionRules: ReaderDocumentProjectionRules(blockSeparator: blockSeparator),
                originalURL: originalURL,
                finalURL: finalURL,
                canonicalURL: canonicalURL,
                byline: byline,
                siteName: siteName,
                excerpt: excerpt,
                language: language,
                direction: direction,
                publicationDate: publicationDate
            ),
            articleHTML: articleHTML,
            plainText: plainText,
            blockIndex: ReaderDocumentBlockIndex(
                schemaVersion: ReaderDocumentBlockIndex.currentSchemaVersion,
                blocks: blocks
            )
        )
    }

    private static func paragraphs(in sourceText: String) -> [String] {
        let normalized = sourceText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let fullRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let matches = blankLinePattern.matches(in: normalized, range: fullRange)
        var paragraphs: [String] = []
        var cursor = normalized.startIndex

        for match in matches {
            guard let range = Range(match.range, in: normalized) else { continue }
            appendParagraph(normalized[cursor..<range.lowerBound], to: &paragraphs)
            cursor = range.upperBound
        }
        appendParagraph(normalized[cursor...], to: &paragraphs)
        return paragraphs
    }

    private static func appendParagraph(_ source: Substring, to paragraphs: inout [String]) {
        let paragraph = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if !paragraph.isEmpty { paragraphs.append(paragraph) }
    }

    private static func htmlText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "\n", with: "<br>\n")
    }
}