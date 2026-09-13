// Modified for Pagehum: unified application and command-line naming.
import Foundation
import SwiftData
import Testing
@testable import Pagehum

struct TechBlogDiscoveryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func classifiesOriginalTopicsAndMatchesDomainBoundaries() throws {
        let url = try #require(URL(string: "https://engineering.example.com/system%20design"))
        #expect(TechBlogDiscovery.classify(title: "Postgres replication for LLM inference", url: url)
            == [.ai, .backend, .scaling, .interview])
        #expect(TechBlogDiscovery.classify(title: "A chair for the garden", url: URL(string: "https://example.com")!).isEmpty)
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
        var irrelevant = item(11); irrelevant.title = "Gardening"
        let items = [newer, good, stale, dead, deleted, job, blocked, invalid, undated, future, irrelevant]
        var settings = TechBlogSettings()
        #expect(TechBlogDiscovery.filter(items, settings: settings, now: now).map(\.id) == [1, 2])
        settings.feed = .new
        #expect(TechBlogDiscovery.filter(items, settings: settings, now: now).map(\.id) == [2, 1])
        settings.minimumScore = 50
        #expect(TechBlogDiscovery.filter(items, settings: settings, now: now).map(\.id) == [1])
        settings.topics = [.interview]
        #expect(TechBlogDiscovery.filter(items, settings: settings, now: now).isEmpty)
        settings.topics = []
        #expect(TechBlogDiscovery.filter(items, settings: settings, now: now).isEmpty)
    }

    @Test
    func persistsFiltersIncludingEmptySelectionAndRecoversCorruptData() throws {
        let suite = "TechBlogSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(TechBlogSettings.load(from: defaults) == TechBlogSettings())
        var settings = TechBlogSettings()
        settings.topics = []
        settings.feed = .new
        settings.minimumScore = 70
        settings.importLimit = 5
        settings.save(to: defaults)
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
        var settings = TechBlogSettings()
        settings.topics = []
        await #expect(throws: TechBlogDiscoveryError.self) {
            try await failing.discover(settings: settings)
        }
    }

    private func item(_ id: Int, score: Int = 50) -> HackerNewsItem {
        HackerNewsItem(id: id, type: "story", title: "Postgres internals", url: "https://example.com/\(id)",
                       score: score, time: now.timeIntervalSince1970 - 60)
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
        {"id":\(id),"type":"story","title":"LLM inference","url":"https://example.com/\(id)","score":50,"time":1799999990}
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
}

nonisolated private struct FixedDiscovery: TechBlogDiscovering {
    let paths: [String]
    func discover(settings: TechBlogSettings) async throws -> TechBlogDiscoveryResult {
        TechBlogDiscoveryResult(stories: paths.enumerated().map { index, path in
            TechBlogStory(id: index, title: "LLM", url: URL(string: "https://example.com/\(path)")!,
                         score: 50, submittedAt: Date(), topics: [.ai])
        }, failedItemCount: 1)
    }
}

@MainActor
private final class TechBlogTestExtractor: ContentExtracting {
    var paths: [String] = []
    func extract(from source: ContentSource) async throws -> ReadingContent {
        let url = try #require(source.webURL)
        paths.append(url.path)
        return ReadingContent(title: url.lastPathComponent, body: "Article text.", source: source)
    }
}
