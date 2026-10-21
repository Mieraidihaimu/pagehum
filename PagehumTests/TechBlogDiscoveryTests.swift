// Modified for Pagehum: unified application and command-line naming.
import Foundation
import SwiftData
import Testing
@testable import Pagehum

struct TechBlogDiscoveryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func matchesBlockedDomainBoundaries() {
        for host in ["youtube.com", "www.youtube.com", "chillphysicsenjoyer.substack.com", "news.bbc.com"] {
            #expect(TechBlogDiscovery.isBlocked(URL(string: "https://\(host)/ai")!))
        }
        for host in ["notyoutube.com", "youtube.com.example.org", "engineering.substack.com"] {
            #expect(!TechBlogDiscovery.isBlocked(URL(string: "https://\(host)/ai")!))
        }
    }

    @Test
    func filtersInvalidStaleAndLowScoreStoriesAndSortsBySelectedFeed() {
        let good = item(1, score: 80)
        var newer = item(2, score: 20)
        newer.time = now.timeIntervalSince1970
        var stale = item(3); stale.time = now.addingTimeInterval(-4 * 86400).timeIntervalSince1970
        var dead = item(4); dead.dead = true
        var deleted = item(5); deleted.deleted = true
        var job = item(6); job.type = "job"
        var blocked = item(7); blocked.url = "https://www.youtube.com/ai"
        var invalid = item(8); invalid.url = "file:///ai"
        var undated = item(9); undated.time = nil
        var future = item(10); future.time = now.addingTimeInterval(60).timeIntervalSince1970
        var offTopic = item(11); offTopic.title = "Gardening"
        let items = [newer, good, stale, dead, deleted, job, blocked, invalid, undated, future, offTopic]
        var settings = TechBlogSettings()
        #expect(TechBlogDiscovery.filter(items, settings: settings, now: now).map(\.id) == [1, 11, 2])
        settings.feed = .new
        #expect(TechBlogDiscovery.filter(items, settings: settings, now: now).map(\.id) == [2, 1, 11])
        settings.minimumScore = 50
        #expect(TechBlogDiscovery.filter(items, settings: settings, now: now).map(\.id) == [1, 11])
    }

    @Test
    func filtersByMinimumCommentsAndKeepsCommentCounts() {
        let quiet = item(1)
        let busy = item(2, comments: 40)
        var settings = TechBlogSettings()
        #expect(TechBlogDiscovery.filter([quiet, busy], settings: settings, now: now).map(\.comments) == [0, 40])
        settings.minimumComments = 10
        #expect(TechBlogDiscovery.filter([quiet, busy], settings: settings, now: now).map(\.id) == [2])
    }

    @Test
    func browsesBySortAndMatchesEveryTermInTitlesOrSites() {
        let stories = [
            story(1, "Postgres internals", "https://www.example.com/a", score: 80, comments: 5, age: 3600),
            story(2, "Rust in production", "https://github.com/b", score: 20, comments: 90, age: 60),
            story(3, "Gardening", "https://blog.rust-lang.org/c", score: 50, comments: 10, age: 7200),
        ]
        #expect(stories[0].site == "example.com")
        #expect(TechBlogDiscovery.browse(stories, query: "", sort: .points).map(\.id) == [1, 3, 2])
        #expect(TechBlogDiscovery.browse(stories, query: "", sort: .comments).map(\.id) == [2, 3, 1])
        #expect(TechBlogDiscovery.browse(stories, query: "", sort: .newest).map(\.id) == [2, 1, 3])
        #expect(TechBlogDiscovery.browse(stories, query: "RUST", sort: .points).map(\.id) == [3, 2])
        #expect(TechBlogDiscovery.browse(stories, query: "example postgres", sort: .points).map(\.id) == [1])
        #expect(TechBlogDiscovery.browse(stories, query: "example rust", sort: .points).isEmpty)
    }

    @Test
    func unsavedSkipsLibraryLinksAndDuplicateSubmissionsInOrder() throws {
        let stories = [
            story(1, "Saved", "https://example.com/saved"),
            story(2, "First", "https://example.com/first"),
            story(3, "First again", "https://EXAMPLE.com/first#comments"),
            story(4, "Second", "https://example.com/second"),
        ]
        let saved: Set = [URLImportParser.key(for: try #require(URL(string: "https://example.com/saved")))]
        #expect(TechBlogDiscovery.unsaved(stories, savedKeys: saved).map(\.id) == [2, 4])
    }

    @Test
    func persistsFiltersAndRecoversLegacyAndCorruptData() throws {
        let suite = "TechBlogSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(TechBlogSettings.load(from: defaults) == TechBlogSettings())
        var settings = TechBlogSettings()
        settings.feed = .new
        settings.minimumScore = 70
        settings.minimumComments = 20
        settings.importLimit = 5
        settings.save(to: defaults)
        #expect(TechBlogSettings.load(from: defaults) == settings)
        // Saved before topic filters were removed and comment filters were added.
        let legacy = #"{"topics":["ai"],"feed":"new","storyCount":100,"freshnessDays":3,"minimumScore":70,"importLimit":5}"#
        defaults.set(Data(legacy.utf8), forKey: TechBlogSettings.storageKey)
        settings.minimumComments = 0
        #expect(TechBlogSettings.load(from: defaults) == settings)
        defaults.set(Data("bad json".utf8), forKey: TechBlogSettings.storageKey)
        #expect(TechBlogSettings.load(from: defaults) == TechBlogSettings())
    }

    @Test
    func fetchesBoundedConcurrentItemsAndReportsPartialFailures() async throws {
        let fixture = DiscoveryFixture()
        var settings = TechBlogSettings()
        settings.feed = .new
        settings.storyCount = 12
        let now = now
        let service = TechBlogDiscovery(load: { try await fixture.load($0) }, now: { now })
        let result = try await service.discover(settings: settings)
        #expect(result.stories.count == 11)
        #expect(result.stories.allSatisfy { $0.comments == 7 })
        #expect(result.failedItemCount == 1)
        let paths = await fixture.paths
        #expect(paths.first == "/v0/newstories.json")
        #expect(paths.count == 13)
        #expect(await fixture.peak <= 10)
        #expect(await fixture.peak > 1)
    }

    @Test
    func reportsUnavailableAndPropagatesCancellation() async {
        let failing = TechBlogDiscovery(load: { url in
            if url.lastPathComponent == "topstories.json" { return Data("[1]".utf8) }
            throw URLError(.notConnectedToInternet)
        })
        await #expect(throws: TechBlogDiscoveryError.self) {
            try await failing.discover(settings: TechBlogSettings())
        }
        let cancelled = TechBlogDiscovery(load: { url in
            if url.lastPathComponent == "topstories.json" { return Data("[1]".utf8) }
            throw CancellationError()
        })
        await #expect(throws: CancellationError.self) {
            try await cancelled.discover(settings: TechBlogSettings())
        }
    }

    private func item(_ id: Int, score: Int = 50, comments: Int? = nil) -> HackerNewsItem {
        HackerNewsItem(id: id, type: "story", title: "Postgres internals", url: "https://example.com/\(id)",
                       score: score, time: now.timeIntervalSince1970 - 60, descendants: comments)
    }

    private func story(_ id: Int, _ title: String, _ link: String, score: Int = 50, comments: Int = 0,
                       age: TimeInterval = 60) -> TechBlogStory {
        TechBlogStory(id: id, title: title, url: URL(string: link)!, score: score, comments: comments,
                      submittedAt: now.addingTimeInterval(-age))
    }
}

private actor DiscoveryFixture {
    var paths: [String] = []
    var active = 0
    var peak = 0

    func load(_ url: URL) async throws -> Data {
        paths.append(url.path)
        if url.lastPathComponent == "newstories.json" { return Data("[1,2,3,4,5,6,7,8,9,10,11,12,13]".utf8) }
        active += 1
        peak = max(peak, active)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(10))
        let id = Int(url.deletingPathExtension().lastPathComponent)!
        if id == 2 { throw URLError(.timedOut) }
        return Data("""
        {"id":\(id),"type":"story","title":"LLM inference","url":"https://example.com/\(id)","score":50,"time":1799999990,"descendants":7}
        """.utf8)
    }
}

@MainActor
struct TechBlogImportTests {
    @Test
    func skipsSavedAndDuplicateStoriesBeforeLimitAndKeepsCurrentArticle() async throws {
        let container = try ModelContainer(for: PlaylistItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let extractor = TechBlogTestExtractor()
        let model = ReaderModel(loadModelOnInit: false, contentExtractor: extractor)
        model.modelContext = context
        let savedSettings = UserDefaults.standard.data(forKey: TechBlogSettings.storageKey)
        defer { UserDefaults.standard.set(savedSettings, forKey: TechBlogSettings.storageKey) }
        model.techBlogSettings = TechBlogSettings()
        model.techBlogSettings.importLimit = 2
        model.content = ReadingContent(title: "Current", body: "Keep this.", source: .text("Keep this."))
        context.insert(PlaylistItem(title: "Saved", sourceURL: "https://example.com/saved", sourceType: "url", fullText: "Saved."))
        try context.save()
        let fixture = FixedDiscovery(paths: ["saved#section", "first", "first#duplicate", "second", "third"])
        await model.importLatestTechBlogs(using: fixture)
        #expect(extractor.paths == ["/first", "/second"])
        #expect(model.importResult?.imported == 2)
        #expect(try context.fetchCount(FetchDescriptor<PlaylistItem>()) == 3)
        #expect(model.content?.title == "Current")
        #expect(!model.isLoading)
        #expect(model.importProgress == nil)
        #expect(model.techBlogMessage?.contains("Couldn’t check 1 HN story") == true)

        await model.importLatestTechBlogs(using: FixedDiscovery(paths: ["saved", "first"]))
        #expect(model.importResult == nil)
        #expect(model.techBlogMessage?.contains("already in your library") == true)
        await model.importLatestTechBlogs(using: FixedDiscovery(paths: []))
        #expect(model.techBlogMessage?.contains("No articles matched") == true)
    }

    @Test
    func browsingLoadsWithoutImportingAndImportsOnlyChosenStories() async throws {
        let container = try ModelContainer(for: PlaylistItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let extractor = TechBlogTestExtractor()
        let model = ReaderModel(loadModelOnInit: false, contentExtractor: extractor)
        model.modelContext = context
        let savedSettings = UserDefaults.standard.data(forKey: TechBlogSettings.storageKey)
        defer { UserDefaults.standard.set(savedSettings, forKey: TechBlogSettings.storageKey) }
        model.techBlogSettings = TechBlogSettings()
        model.techBlogSettings.importLimit = 2
        context.insert(PlaylistItem(title: "Saved", sourceURL: "https://example.com/saved", sourceType: "url", fullText: "Saved."))
        try context.save()

        await model.loadTechBlogStories(using: FixedDiscovery(paths: ["saved", "first", "first#duplicate", "second", "third"]))
        #expect(model.techBlogStories.count == 5)
        #expect(model.isInLibrary(model.techBlogStories[0]))
        #expect(extractor.paths.isEmpty)
        #expect(model.techBlogMessage?.contains("Couldn’t check 1 HN story") == true)

        await model.importTechBlogStories([model.techBlogStories[4]])
        #expect(extractor.paths == ["/third"])
        #expect(model.isInLibrary(model.techBlogStories[4]))
        #expect(!model.isLoading)
    }

    @Test
    func retryingFailedLinksRefreshesStorySavedBadges() async throws {
        let container = try ModelContainer(for: PlaylistItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let extractor = TechBlogTestExtractor()
        extractor.failingPaths = ["/retry"]
        let model = ReaderModel(loadModelOnInit: false, contentExtractor: extractor)
        model.modelContext = ModelContext(container)
        await model.loadTechBlogStories(using: FixedDiscovery(paths: ["retry"]))
        let story = try #require(model.techBlogStories.first)

        await model.importTechBlogStories([story])
        #expect(!model.isInLibrary(story))
        let failures = try #require(model.importResult).failures
        #expect(failures.count == 1)
        extractor.failingPaths.removeAll()
        let result = try #require(await model.importURLs(from: failures.map { $0.url.absoluteString }.joined(separator: "\n")))
        #expect(result.imported == 1)
        #expect(model.isInLibrary(story))
        #expect(model.content == nil)
        #expect(try model.modelContext?.fetchCount(FetchDescriptor<PlaylistItem>()) == 1)
    }
}

nonisolated private struct FixedDiscovery: TechBlogDiscovering {
    let paths: [String]
    func discover(settings: TechBlogSettings) async throws -> TechBlogDiscoveryResult {
        TechBlogDiscoveryResult(stories: paths.enumerated().map { index, path in
            TechBlogStory(id: index, title: "LLM", url: URL(string: "https://example.com/\(path)")!,
                         score: 50, comments: 0, submittedAt: Date())
        }, failedItemCount: 1)
    }
}

@MainActor
private final class TechBlogTestExtractor: ContentExtracting {
    var paths: [String] = []
    var failingPaths: Set<String> = []
    func extract(from source: ContentSource) async throws -> ReadingContent {
        let url = try #require(source.webURL)
        paths.append(url.path)
        if failingPaths.contains(url.path) { throw URLError(.cannotLoadFromNetwork) }
        return ReadingContent(title: url.lastPathComponent, body: "Article text.", source: source)
    }
}
