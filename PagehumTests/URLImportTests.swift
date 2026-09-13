// Modified for Pagehum: unified application and command-line naming.
import Foundation
import SwiftData
import Testing
@testable import Pagehum

@MainActor
struct URLImportTests {
    @Test
    func detectsMixedSeparatorsAndLinksInProse() {
        let links = URLImportParser.urls(in: "Read [this](https://example.com/a),https://example.org/b\nwww.apple.com\texample.net/c and https://example.com/end.")
        #expect(links.map(\.absoluteString) == [
            "https://example.com/a", "https://example.org/b", "https://www.apple.com",
            "https://example.net/c", "https://example.com/end"
        ])
    }

    @Test
    func ignoresNonWebTextAndDeduplicatesWithoutDiscardingQueries() {
        #expect(URLImportParser.urls(in: "Some prose, person@example.com ftp://example.com/file javascript:alert(1)").isEmpty)
        let links = URLImportParser.urls(in: "https://example.com/a#first https://EXAMPLE.com:443/a#second https://example.com/a?q=1 https://example.com/a?q=2")
        #expect(links.count == 3)
        #expect(links[1].query == "q=1")
        #expect(links[2].query == "q=2")
    }

    @Test
    func importsIndependentlySkipsSavedLinksAndRetriesFailures() async throws {
        let container = try ModelContainer(for: PlaylistItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let extractor = ImportTestExtractor()
        let model = ReaderModel(loadModelOnInit: false, contentExtractor: extractor)
        model.modelContext = context
        model.content = ReadingContent(title: "Current", body: "Keep this text.", source: .text("Keep this text."))
        model.prepareTextPublic("Keep this text.")
        let existing = PlaylistItem(title: "Saved", sourceURL: "https://example.com/saved", sourceType: "url", fullText: "Saved text.")
        context.insert(existing)
        try context.save()

        let result = try #require(await model.importURLs(from: "https://example.com/saved#section,https://example.com/first https://example.com/broken\nhttps://example.com/last https://example.com/first"))
        #expect(result.imported == 2)
        #expect(result.skipped == 1)
        #expect(result.failures.map { $0.url.path } == ["/broken"])
        #expect(extractor.paths == ["/first", "/broken", "/last"])
        #expect(try context.fetchCount(FetchDescriptor<PlaylistItem>()) == 3)
        #expect(model.content?.title == "Current")
        #expect(model.sentences == ["Keep this text."])
        #expect(!model.isLoading)
        #expect(model.importProgress == nil)

        extractor.shouldFail = false
        let retry = try #require(await model.importURLs(from: result.failures.map { $0.url.absoluteString }.joined(separator: "\n")))
        #expect(retry.imported == 1)
        #expect(retry.failures.isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<PlaylistItem>()) == 4)
        let imported = try context.fetch(FetchDescriptor<PlaylistItem>()).filter { $0 !== existing }
        #expect(imported.allSatisfy { $0.status == PlaylistItem.Status.queued.rawValue })
    }

    @Test
    func rejectsMissingLinksOrUnavailableLibraryWithoutReportingSuccess() async {
        let model = ReaderModel(loadModelOnInit: false, contentExtractor: ImportTestExtractor())
        let invalid = await model.importURLs(from: "no links here")
        #expect(invalid == nil)
        #expect(model.errorMessage != nil)
        let unavailable = await model.importURLs(from: "https://example.com/article")
        #expect(unavailable == nil)
        #expect(model.importResult == nil)
        #expect(!model.isLoading)
    }
}

@MainActor
private final class ImportTestExtractor: ContentExtracting {
    var paths: [String] = []
    var shouldFail = true

    func extract(from source: ContentSource) async throws -> ReadingContent {
        let url = try #require(source.webURL)
        paths.append(url.path)
        if shouldFail && url.path == "/broken" { throw URLError(.cannotLoadFromNetwork) }
        return ReadingContent(title: url.lastPathComponent, body: "Imported article text.", source: source)
    }
}
