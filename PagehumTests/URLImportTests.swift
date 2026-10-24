// Modified for Pagehum: unified application and command-line naming.
import Foundation
import SwiftData
import Testing
@testable import Pagehum

@MainActor
struct URLImportTests {
    @Test
    func sharedLinkIsRetainedOnFailureAndAcknowledgedAfterDurableImport() async throws {
        let suite = "SharedImportTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try ModelContainer(for: PlaylistItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let extractor = ImportTestExtractor()
        let model = ReaderModel(loadModelOnInit: false, contentExtractor: extractor)
        model.modelContext = container.mainContext
        let link = "https://example.com/broken?first=1&second=two,three#section"
        defaults.set(link, forKey: "SharedURL")
        model.checkForSharedURL(from: defaults)
        await model.loadPendingSharedURL(from: defaults)
        #expect(model.errorMessage != nil)
        #expect(defaults.string(forKey: "SharedURL") == link)
        #expect(model.pendingSharedURL == link)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<PlaylistItem>()) == 0)

        extractor.shouldFail = false
        await model.loadPendingSharedURL(from: defaults)
        #expect(model.errorMessage == nil)
        #expect(defaults.string(forKey: "SharedURL") == nil)
        #expect(model.pendingSharedURL == nil)
        #expect(model.content?.source.webURL?.absoluteString == link)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<PlaylistItem>()) == 1)

        defaults.set(link, forKey: "SharedURL")
        model.checkForSharedURL(from: defaults)
        await model.loadPendingSharedURL(from: defaults)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<PlaylistItem>()) == 1)
        #expect(defaults.string(forKey: "SharedURL") == nil)
    }

    @Test(arguments: ["file:///etc/passwd", "javascript:alert(1)", "ftp://example.com/file", "https://"])
    func rejectsNonWebDeepLinkTargets(target: String) {
        let model = ReaderModel(loadModelOnInit: false)
        var link = URLComponents()
        link.scheme = "pagehum"
        link.host = "open"
        link.queryItems = [URLQueryItem(name: "url", value: target)]
        model.handleOpenURL(link.url!)
        #expect(model.pendingSharedURL == nil)
    }

    @Test
    func discardingFailedShareDoesNotDeleteANewerHandoff() throws {
        let suite = "SharedDiscardTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ReaderModel(loadModelOnInit: false)
        defaults.set("https://example.com/first", forKey: "SharedURL")
        model.checkForSharedURL(from: defaults)
        defaults.set("https://example.com/second", forKey: "SharedURL")
        model.discardPendingSharedURL(from: defaults)
        #expect(model.pendingSharedURL == nil)
        #expect(defaults.string(forKey: "SharedURL") == "https://example.com/second")
        model.checkForSharedURL(from: defaults)
        model.discardPendingSharedURL(from: defaults)
        #expect(defaults.string(forKey: "SharedURL") == nil)
    }

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
    func summaryListsOnlyNonZeroCounts() throws {
        let failure = URLImportResult.Failure(url: try #require(URL(string: "https://example.com")), message: "Timed out")
        #expect(URLImportResult(imported: 3).summary == "3 imported")
        #expect(URLImportResult(skipped: 1).summary == "1 already saved")
        #expect(URLImportResult(imported: 2, skipped: 1, failures: [failure]).summary == "2 imported · 1 already saved · 1 failed")
        #expect(URLImportResult().summary == "Nothing imported")
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
        #expect(result.singleItem == nil)
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
    func singleUniqueURLCanOpenAfterImportWithoutExtractingAgain() async throws {
        let container = try ModelContainer(for: PlaylistItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let extractor = ImportTestExtractor()
        let model = ReaderModel(loadModelOnInit: false, contentExtractor: extractor)
        model.modelContext = context

        let result = try #require(await model.importURLs(from: "https://example.com/article https://EXAMPLE.com:443/article#section"))
        let item = try #require(result.singleItem)
        #expect(result.imported == 1)
        #expect(model.openLibraryItem(item))
        #expect(model.content?.source.webURL?.absoluteString == "https://example.com/article")
        #expect(model.sentences == ["Imported article text."])
        #expect(model.currentPlaylistItemID == item.persistentModelID)
        #expect(extractor.paths == ["/article"])
        #expect(try context.fetchCount(FetchDescriptor<PlaylistItem>()) == 1)
        #expect(!model.isPlaying)
        #expect(!model.isPreparing)
    }

    @Test
    func singleSavedURLCanResumeWithoutCreatingAnotherCopy() async throws {
        let container = try ModelContainer(for: PlaylistItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let extractor = ImportTestExtractor()
        let model = ReaderModel(loadModelOnInit: false, contentExtractor: extractor)
        model.modelContext = context
        let existing = PlaylistItem(title: "Saved", sourceURL: "https://example.com/saved", sourceType: "url",
                                    fullText: "First sentence. Second sentence.")
        existing.lastSentenceIndex = 1
        existing.playbackTextOffset = "First sentence. ".utf16.count
        existing.progressPercent = 0.5
        context.insert(existing)
        try context.save()

        let result = try #require(await model.importURLs(from: "https://EXAMPLE.com:443/saved#section"))
        let item = try #require(result.singleItem)
        #expect(result.imported == 0)
        #expect(result.skipped == 1)
        #expect(item === existing)
        #expect(model.openLibraryItem(item))
        #expect(model.currentSentenceIndex == 1)
        #expect(model.progress == 0.5)
        #expect(extractor.paths.isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<PlaylistItem>()) == 1)
        #expect(!model.isPlaying)
    }

    @Test
    func failedSingleURLAndPartiallySuccessfulBatchDoNotOfferAnArticleToOpen() async throws {
        let container = try ModelContainer(for: PlaylistItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = ReaderModel(loadModelOnInit: false, contentExtractor: ImportTestExtractor())
        model.modelContext = ModelContext(container)
        model.content = ReadingContent(title: "Current", body: "Keep this text.", source: .text("Keep this text."))
        model.prepareTextPublic("Keep this text.")

        let failed = try #require(await model.importURLs(from: "https://example.com/broken"))
        #expect(failed.singleItem == nil)
        #expect(failed.failures.count == 1)
        let batch = try #require(await model.importURLs(from: "https://example.com/article https://example.com/broken"))
        #expect(batch.imported == 1)
        #expect(batch.failures.count == 1)
        #expect(batch.singleItem == nil)
        #expect(model.content?.title == "Current")
        #expect(model.sentences == ["Keep this text."])
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
