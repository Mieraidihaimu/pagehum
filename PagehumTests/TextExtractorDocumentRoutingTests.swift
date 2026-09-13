// Modified for Pagehum: unified application and command-line naming.
import Testing
@testable import Pagehum

@MainActor
struct TextExtractorDocumentRoutingTests {
    @Test
    func pastedTextCarriesItsDeterministicReaderDocument() async throws {
        let source = "First paragraph.\n\nSecond paragraph."

        let content = try await TextExtractor().extract(from: .text(source))
        let document = try #require(content.readerDocument)

        #expect(content.body == document.plainText)
        #expect(document.manifest.sourceKind == .text)
        #expect(document.blocks.count == 2)
        try document.validateProjection()
    }
}