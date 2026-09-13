// Modified for Pagehum: unified application and command-line naming.
import Foundation
import Testing
@testable import Pagehum

@MainActor
struct ReaderWebDocumentExtractorTests {
    @Test
    func extractsSanitizedDocumentInIsolatedWorldAfterDOMQuiescence() async throws {
        let fixtureURL = try #require(
            Bundle(for: FixtureBundleToken.self).url(
                forResource: "reader-article",
                withExtension: "html",
                subdirectory: "Fixtures"
            ) ?? Bundle(for: FixtureBundleToken.self).url(
                forResource: "reader-article",
                withExtension: "html"
            )
        )
        let html = try String(contentsOf: fixtureURL, encoding: .utf8)
        let sourceURL = try #require(URL(string: "https://example.com/articles/story"))
        let createdAt = Date(timeIntervalSince1970: 3_000)

        let document = try await ReaderWebDocumentExtractor().extract(
            html: html,
            baseURL: sourceURL,
            createdAt: createdAt
        )

        #expect(document.manifest.sourceKind == .url)
        #expect(document.manifest.title == "Local Reader Fixture")
        #expect(document.manifest.byline == "Ada Example")
        #expect(document.manifest.siteName == "Fixture Journal")
        #expect(document.manifest.originalURL == sourceURL)
        #expect(document.manifest.finalURL == sourceURL)
        #expect(document.manifest.canonicalURL?.absoluteString == "https://example.com/canonical-story")
        #expect(document.manifest.language == "en")
        #expect(document.manifest.direction == "ltr")
        #expect(document.manifest.createdAt == createdAt)

        #expect(document.plainText.contains("Late paragraph captured after the page becomes quiet."))
        #expect(document.plainText.contains("Line before a break.\nLine after the break"))
        #expect(document.plainText.occurrences(of: "Nested list paragraph appears once") == 1)
        #expect(document.plainText.occurrences(of: "A quoted paragraph remains one block") == 1)
        #expect(document.plainText.contains("let greeting = \"hello\"\nprint(greeting)"))
        #expect(!document.plainText.contains("PUBLISHER TAMPER"))

        #expect(document.blocks.contains { $0.kind == .code && !$0.isSpeakable })
        #expect(document.blocks.contains { $0.kind == .listItem && $0.isSpeakable })
        #expect(document.blocks.contains { $0.kind == .quote && $0.isSpeakable })
        #expect(document.articleHTML.contains("data-pagehum-block-id="))
        #expect(document.articleHTML.contains("href=\"https://example.com/related\""))
        #expect(document.articleHTML.contains("src=\"https://example.com/images/cover.jpg\""))
        #expect(!document.articleHTML.localizedCaseInsensitiveContains("<script"))
        #expect(!document.articleHTML.localizedCaseInsensitiveContains("<style"))
        #expect(!document.articleHTML.localizedCaseInsensitiveContains("<form"))
        #expect(!document.articleHTML.localizedCaseInsensitiveContains("onclick="))
        #expect(!document.articleHTML.localizedCaseInsensitiveContains("onerror="))
        #expect(!document.articleHTML.localizedCaseInsensitiveContains("javascript:"))

        try document.validateProjection()
    }
}

private final class FixtureBundleToken: NSObject {}

private extension String {
    func occurrences(of needle: String) -> Int {
        components(separatedBy: needle).count - 1
    }
}