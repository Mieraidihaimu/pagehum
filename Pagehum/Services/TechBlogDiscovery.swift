// Modified for Pagehum: unified application and command-line naming.
import Foundation

nonisolated enum TechBlogSource: String, CaseIterable, Codable, Sendable, Identifiable {
    case hackerNews, lobsters, blogFeeds

    var id: String { rawValue }
    var title: String {
        switch self {
        case .hackerNews: "Hacker News"
        case .lobsters: "Lobsters"
        case .blogFeeds: "Blog feeds"
        }
    }
}

nonisolated enum TechBlogFeed: String, CaseIterable, Codable, Sendable, Identifiable {
    case top, new
    var id: String { rawValue }
    var title: String { self == .top ? "Top stories" : "Newest stories" }
}

nonisolated enum TechBlogSort: String, CaseIterable, Sendable, Identifiable {
    case newest, points, comments
    var id: String { rawValue }
    var title: String {
        switch self {
        case .points: "Points"
        case .comments: "Comments"
        case .newest: "Newest"
        }
    }
}

nonisolated struct TechBlogSettings: Codable, Equatable, Sendable {
    var source: TechBlogSource = .hackerNews
    var feed: TechBlogFeed = .top
    var storyCount = 100
    var freshnessDays = 3
    var minimumScore = 0
    var minimumComments = 0
    var lobstersMinimumScore = 0
    var lobstersMinimumComments = 0
    var importLimit = 10

    static let storageKey = "techBlogImportSettings"

    var validated: Self {
        var value = self
        value.storyCount = min(500, max(1, storyCount))
        value.freshnessDays = min(7, max(1, freshnessDays))
        value.minimumScore = min(1000, max(0, minimumScore))
        value.minimumComments = min(1000, max(0, minimumComments))
        value.lobstersMinimumScore = min(1000, max(0, lobstersMinimumScore))
        value.lobstersMinimumComments = min(1000, max(0, lobstersMinimumComments))
        value.importLimit = min(50, max(1, importLimit))
        return value
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return settings.validated
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(validated) { defaults.set(data, forKey: Self.storageKey) }
    }
}

nonisolated extension TechBlogSettings {
    // Keys added in later versions fall back to defaults instead of resetting every preference.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self()
        source = try container.decodeIfPresent(TechBlogSource.self, forKey: .source) ?? fallback.source
        feed = try container.decodeIfPresent(TechBlogFeed.self, forKey: .feed) ?? fallback.feed
        storyCount = try container.decodeIfPresent(Int.self, forKey: .storyCount) ?? fallback.storyCount
        freshnessDays = try container.decodeIfPresent(Int.self, forKey: .freshnessDays) ?? fallback.freshnessDays
        minimumScore = try container.decodeIfPresent(Int.self, forKey: .minimumScore) ?? fallback.minimumScore
        minimumComments = try container.decodeIfPresent(Int.self, forKey: .minimumComments) ?? fallback.minimumComments
        lobstersMinimumScore = try container.decodeIfPresent(Int.self, forKey: .lobstersMinimumScore) ?? fallback.lobstersMinimumScore
        lobstersMinimumComments = try container.decodeIfPresent(Int.self, forKey: .lobstersMinimumComments) ?? fallback.lobstersMinimumComments
        importLimit = try container.decodeIfPresent(Int.self, forKey: .importLimit) ?? fallback.importLimit
    }
}

nonisolated struct HackerNewsItem: Decodable, Sendable {
    let id: Int
    var type: String? = nil
    var title: String? = nil
    var url: String? = nil
    var score: Int? = nil
    var time: TimeInterval? = nil
    var dead: Bool? = nil
    var deleted: Bool? = nil
    var descendants: Int? = nil
}

nonisolated private struct LobstersStory: Decodable, Sendable {
    let shortId: String
    let createdAt: String
    let title: String
    let url: String?
    let score: Int
    let commentCount: Int
}

nonisolated struct TechBlogStory: Sendable, Identifiable {
    let id: String
    let title: String
    let url: URL
    var score: Int? = nil
    var comments: Int? = nil
    let date: Date
    var discussionURL: URL? = nil

    var site: String {
        let host = url.host?.lowercased() ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

nonisolated struct TechBlogDiscoveryResult: Sendable {
    var stories: [TechBlogStory]
    var failedItemCount = 0
}

nonisolated protocol TechBlogDiscovering: Sendable {
    func discover(settings: TechBlogSettings) async throws -> TechBlogDiscoveryResult
}

nonisolated enum TechBlogDiscoveryError: LocalizedError {
    case unavailable(TechBlogSource)

    var errorDescription: String? {
        switch self {
        case .unavailable(let source): "Couldn’t fetch stories from \(source.title). Please try again."
        }
    }
}

/// Fetches story metadata. Article extraction remains in the library importer.
nonisolated struct TechBlogDiscovery: TechBlogDiscovering {
    typealias Loader = @Sendable (URL) async throws -> Data
    private let load: Loader
    private let now: @Sendable () -> Date
    private static let hackerNewsAPI = URL(string: "https://hacker-news.firebaseio.com/v0/")!

    init(load: @escaping Loader = { try await TechBlogDiscovery.fetch($0) }, now: @escaping @Sendable () -> Date = { Date() }) {
        self.load = load
        self.now = now
    }

    static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Pagehum/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    func discover(settings: TechBlogSettings) async throws -> TechBlogDiscoveryResult {
        let settings = settings.validated
        try Task.checkCancellation()
        do {
            switch settings.source {
            case .hackerNews: return try await hackerNews(settings)
            case .lobsters: return try await lobsters(settings)
            case .blogFeeds: return try await blogFeeds()
            }
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            throw TechBlogDiscoveryError.unavailable(settings.source)
        }
    }

    private func hackerNews(_ settings: TechBlogSettings) async throws -> TechBlogDiscoveryResult {
        let data = try await load(Self.hackerNewsAPI.appendingPathComponent("\(settings.feed.rawValue)stories.json"))
        let ids = try JSONDecoder().decode([Int].self, from: data)
        var seen = Set<Int>()
        let selected = Array(ids.filter { $0 > 0 && seen.insert($0).inserted }.prefix(settings.storyCount))
        let loaded = try await withThrowingTaskGroup(of: HackerNewsItem?.self) { group in
            var iterator = selected.makeIterator()
            func enqueue(_ id: Int) {
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        let data = try await load(Self.hackerNewsAPI.appendingPathComponent("item/\(id).json"))
                        return try JSONDecoder().decode(HackerNewsItem?.self, from: data)
                    } catch {
                        try Task.checkCancellation()
                        if error is CancellationError { throw error }
                        return nil
                    }
                }
            }
            // Bound requests so a large scan doesn't open hundreds of connections.
            for _ in 0..<min(10, selected.count) {
                if let id = iterator.next() { enqueue(id) }
            }
            var items: [HackerNewsItem] = []
            var failed = 0
            while let item = try await group.next() {
                if let item { items.append(item) } else { failed += 1 }
                if let id = iterator.next() { enqueue(id) }
            }
            return (items, failed)
        }
        try Task.checkCancellation()
        if !selected.isEmpty && loaded.0.isEmpty { throw TechBlogDiscoveryError.unavailable(.hackerNews) }
        return TechBlogDiscoveryResult(
            stories: Self.filter(loaded.0, settings: settings, now: now()),
            failedItemCount: loaded.1
        )
    }

    private func lobsters(_ settings: TechBlogSettings) async throws -> TechBlogDiscoveryResult {
        let path = settings.feed == .top ? "hottest.json" : "newest.json"
        let data = try await load(URL(string: "https://lobste.rs/\(path)")!)
        try Task.checkCancellation()
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let items = try decoder.decode([LobstersStory].self, from: data)
        let now = now()
        let cutoff = now.addingTimeInterval(-Double(settings.freshnessDays) * 86400)
        let iso = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stories = items.compactMap { item -> TechBlogStory? in
            guard let rawURL = item.url, let url = Self.articleURL(rawURL), !Self.isBlocked(url), url.host?.lowercased() != "lobste.rs",
                  !item.title.isEmpty,
                  let date = fractional.date(from: item.createdAt) ?? iso.date(from: item.createdAt),
                  (cutoff...now).contains(date),
                  item.score >= settings.lobstersMinimumScore,
                  item.commentCount >= settings.lobstersMinimumComments else { return nil }
            let discussion = URL(string: "https://lobste.rs/s/")?.appendingPathComponent(item.shortId)
            return TechBlogStory(id: "lobsters:\(item.shortId)", title: item.title, url: url,
                                 score: item.score, comments: item.commentCount, date: date, discussionURL: discussion)
        }
        // The hottest feed already ranks stories using Lobsters' voting and tag weights.
        return TechBlogDiscoveryResult(stories: Self.unsaved(stories, savedKeys: []))
    }

    private func blogFeeds() async throws -> TechBlogDiscoveryResult {
        let now = now()
        return try await withThrowingTaskGroup(of: [TechBlogStory]?.self) { group in
            for url in TechBlogSyndication.feeds {
                group.addTask {
                    do {
                        let data = try await load(url)
                        try Task.checkCancellation()
                        return try TechBlogSyndication.stories(from: data, feedURL: url, now: now)
                    } catch {
                        try Task.checkCancellation()
                        if error is CancellationError { throw error }
                        return nil
                    }
                }
            }
            var stories: [TechBlogStory] = []
            var failed = 0
            for try await batch in group {
                if let batch { stories.append(contentsOf: batch) } else { failed += 1 }
            }
            try Task.checkCancellation()
            if failed == TechBlogSyndication.feeds.count { throw TechBlogDiscoveryError.unavailable(.blogFeeds) }
            let ordered = Self.browse(stories, query: "", sort: .newest)
            return TechBlogDiscoveryResult(stories: Self.unsaved(ordered, savedKeys: []), failedItemCount: failed)
        }
    }

    static func articleURL(_ rawURL: String, relativeTo baseURL: URL? = nil) -> URL? {
        guard !rawURL.isEmpty, let url = URL(string: rawURL, relativeTo: baseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    static func isBlocked(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) else { return true }
        return blockedDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func filter(_ items: [HackerNewsItem], settings: TechBlogSettings, now: Date) -> [TechBlogStory] {
        let settings = settings.validated
        let cutoff = now.addingTimeInterval(-Double(settings.freshnessDays) * 86400)
        return items.compactMap { item -> TechBlogStory? in
            guard item.type == "story", item.dead != true, item.deleted != true,
                  let title = item.title, !title.isEmpty,
                  let rawURL = item.url, let url = articleURL(rawURL), !isBlocked(url),
                  let time = item.time, time.isFinite,
                  time >= cutoff.timeIntervalSince1970, time <= now.timeIntervalSince1970,
                  (item.score ?? 0) >= settings.minimumScore,
                  (item.descendants ?? 0) >= settings.minimumComments else { return nil }
            return TechBlogStory(id: String(item.id), title: title, url: url, score: item.score ?? 0,
                                 comments: item.descendants ?? 0, date: Date(timeIntervalSince1970: time),
                                 discussionURL: URL(string: "https://news.ycombinator.com/item?id=\(item.id)"))
        }.sorted {
            if settings.feed == .top && $0.score != $1.score { return ($0.score ?? 0) > ($1.score ?? 0) }
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.id.compare($1.id, options: .numeric) == .orderedAscending
        }
    }

    /// Stories whose links aren't in the library yet, without duplicate submissions, in discovery order.
    static func unsaved(_ stories: [TechBlogStory], savedKeys: Set<String>) -> [TechBlogStory] {
        var seen = savedKeys
        return stories.filter { seen.insert(URLImportParser.key(for: $0.url)).inserted }
    }

    /// Every search term must appear in the title or site.
    static func browse(_ stories: [TechBlogStory], query: String, sort: TechBlogSort) -> [TechBlogStory] {
        let terms = query.split(whereSeparator: \.isWhitespace)
        return stories.filter { story in
            terms.allSatisfy { term in
                [story.title, story.site].contains { $0.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            }
        }.sorted { a, b in
            switch sort {
            case .points where a.score != b.score: return (a.score ?? 0) > (b.score ?? 0)
            case .comments where a.comments != b.comments: return (a.comments ?? 0) > (b.comments ?? 0)
            default: break
            }
            if a.date != b.date { return a.date > b.date }
            return a.id.compare(b.id, options: .numeric) == .orderedAscending
        }
    }
}

nonisolated private extension TechBlogDiscovery {
    // Source exclusions ported from the supplied hn-filter script.
    static let blockedDomains: Set<String> = [
        "amazon.com",
        "apple.com",
        "archive.org",
        "bbc.com",
        "bloomberg.com",
        "bnext.bio",
        "bsky.app",
        "chillphysicsenjoyer.substack.com",
        "consumerrights.wiki",
        "cxmt.com",
        "devz.cl",
        "gizmodo.com",
        "graphsaboutreligion.com",
        "gwern.net",
        "hackaday.com",
        "honestlyranked.com",
        "instagram.com",
        "interconnected.org",
        "k-monk.org",
        "labguysworld.com",
        "lanparty.house",
        "latimes.com",
        "ligo.caltech.edu",
        "marketingdive.com",
        "mastodon.social",
        "mathstodon.xyz",
        "mbugert.de",
        "mrdee.in",
        "newyorker.com",
        "nomanssky.com",
        "not-ship.com",
        "nytimes.com",
        "opusfived.dev",
        "propublica.org",
        "pv-magazine.com",
        "reddit.com",
        "reuters.com",
        "scri.ch",
        "shatteredpixel.com",
        "smithsonianmag.com",
        "stockfishchess.org",
        "taoofmac.com",
        "techcrunch.com",
        "techradar.com",
        "theatlantic.com",
        "thelec.net",
        "threads.net",
        "turdle.fun",
        "twitter.com",
        "variety.com",
        "wikipedia.org",
        "x.com",
        "ycombinator.com",
        "youtu.be",
        "youtube.com",
    ]
}
