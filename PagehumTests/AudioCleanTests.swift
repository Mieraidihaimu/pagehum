// Modified for Pagehum: unified application and command-line naming.
import Foundation
import Testing
@testable import Pagehum

struct AudioCleanTests {

    // MARK: - AudioCleanFilter & In-Text Citation Stripping

    @Test
    func stripsBracketedNumericCitationsAndPreservesPunctuation() {
        let input = "Swift was announced in 2014 [1]. It was later open-sourced [2, 3]."
        let mapping = AudioCleanFilter.cleanForSpeech(input)

        #expect(mapping.displayText == input)
        #expect(mapping.spokenText == "Swift was announced in 2014. It was later open-sourced.")
        #expect(mapping.shifts.count == 2)
    }

    @Test
    func stripsNamedCitationsAndSuperscripts() {
        let input = "Claims require evidence [citation needed] and further details [note 12]. Version 2² is fast."
        let mapping = AudioCleanFilter.cleanForSpeech(input)

        #expect(mapping.displayText == input)
        #expect(mapping.spokenText == "Claims require evidence and further details. Version 2 is fast.")
    }

    @Test
    func preservesCodeAndMathBrackets() {
        let input = "Look at array[0] and interval [0, 1] in [A-Z]."
        let mapping = AudioCleanFilter.cleanForSpeech(input)

        // None of these should be stripped because they are indexing or ranges
        #expect(mapping.spokenText == input)
        #expect(mapping.shifts.isEmpty)
    }

    @Test
    func mapsSpokenTokenRangesBackToDisplayRangesAccurately() {
        let input = "Alpha [1] beta [2, 3] gamma."
        let mapping = AudioCleanFilter.cleanForSpeech(input)
        #expect(mapping.spokenText == "Alpha beta gamma.")

        let spokenStr = mapping.spokenText as NSString
        let displayStr = mapping.displayText as NSString

        // Token "Alpha"
        let alphaSpokenRange = spokenStr.range(of: "Alpha")
        let alphaDisplayRange = mapping.displayRange(forSpokenRange: alphaSpokenRange)
        #expect(displayStr.substring(with: alphaDisplayRange) == "Alpha")

        // Token "beta"
        let betaSpokenRange = spokenStr.range(of: "beta")
        let betaDisplayRange = mapping.displayRange(forSpokenRange: betaSpokenRange)
        #expect(displayStr.substring(with: betaDisplayRange) == "beta")

        // Token "gamma"
        let gammaSpokenRange = spokenStr.range(of: "gamma")
        let gammaDisplayRange = mapping.displayRange(forSpokenRange: gammaSpokenRange)
        #expect(displayStr.substring(with: gammaDisplayRange) == "gamma")
    }

    // MARK: - TableBlock

    @Test
    func parsesTabDelimitedTableAndProducesAnnouncementAndNeedle() {
        let rawTable = """
        Language\tCreator\tYear
        Swift\tApple\t2014
        Rust\tGraydon Hoare\t2010
        Go\tGoogle\t2009
        """
        let table = TableBlock(rawText: rawTable, caption: "Language Comparison")

        #expect(table.columnCount == 3)
        #expect(table.rowCount == 4) // 1 header + 3 rows
        #expect(table.headers == ["Language", "Creator", "Year"])
        #expect(table.rows.count == 3)
        #expect(table.spokenAnnouncement == "Table with 3 columns and 4 rows, Language Comparison.")
        #expect(table.firstSubstantialCell == "Language Comparison")
        #expect(table.verbatimText.contains("Swift, Apple, 2014"))
    }

    // MARK: - ReaderDocument Projection with AudioCleanMode

    @Test
    func projectsDocumentWithCleanAnnouncementsAndCitationStripping() {
        let prose = "First sentence with reference [1]. Second sentence."
        let code = "let count = 42"
        let tableText = "A\tB\n1\t2"

        let doc = ReaderDocumentBuilder.webArticle(
            title: "Test Article",
            articleHTML: "<article></article>",
            projectedBlocks: [
                ReaderDocumentProjectedBlock(id: "block-001", kind: .prose, isSpeakable: true, text: prose),
                ReaderDocumentProjectedBlock(id: "block-002", kind: .code, isSpeakable: false, text: code),
                ReaderDocumentProjectedBlock(id: "block-003", kind: .table, isSpeakable: true, text: tableText),
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

        // Clean mode projection
        let clean = ReaderDocumentSentenceProjector.segment(doc, mode: .clean) { text in
            text.components(separatedBy: ". ").filter { !$0.isEmpty }.map { $0.hasSuffix(".") ? $0 : $0 + "." }
        }

        #expect(clean.sentences.count == 4) // 2 prose sentences + 1 code announcement + 1 table announcement
        #expect(clean.codeBlocks[2] != nil)
        #expect(clean.tableBlocks[3] != nil)
        #expect(clean.sentences[2] == "Code, one line.")
        #expect(clean.sentences[3] == "Table, 2 columns and 2 rows.")

        // First prose sentence should have spoken text mapping without [1]
        let firstMapping = clean.spokenTextMappings[0]
        #expect(firstMapping?.spokenText == "First sentence with reference.")

        // Verbatim mode projection
        let verbatim = ReaderDocumentSentenceProjector.segment(doc, mode: .verbatim) { text in
            text.components(separatedBy: ". ").filter { !$0.isEmpty }.map { $0.hasSuffix(".") ? $0 : $0 + "." }
        }
        #expect(verbatim.sentences[2] == code)
        #expect(verbatim.spokenTextMappings[0] == nil) // Verbatim does not strip citations
    }

    // MARK: - PlaylistItem Persistence Roundtrip

    @Test
    func roundtripsReaderDocumentThroughPlaylistItemExternalStorage() throws {
        let prose = "Hello world."
        let doc = ReaderDocumentBuilder.webArticle(
            title: "Roundtrip Test",
            articleHTML: "<article><p>Hello world.</p></article>",
            projectedBlocks: [
                ReaderDocumentProjectedBlock(id: "b1", kind: .prose, isSpeakable: true, text: prose)
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

        let encoded = try JSONEncoder().encode(doc)
        let item = PlaylistItem(
            title: doc.manifest.title,
            sourceURL: "https://example.com",
            sourceType: "url",
            fullText: doc.plainText,
            readerDocumentData: encoded
        )

        #expect(item.readerDocumentData != nil)
        let decoded = try JSONDecoder().decode(ReaderDocument.self, from: try #require(item.readerDocumentData))
        #expect(decoded.manifest.title == "Roundtrip Test")
        #expect(decoded.blocks.count == 1)
        #expect(decoded.plainText == doc.plainText)
    }
}
