// Modified for Pagehum: unified application and command-line naming.
import Foundation

nonisolated enum TechBlogTopic: String, CaseIterable, Codable, Sendable, Identifiable {
    case ai, backend, scaling, interview
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ai: "AI"
        case .backend: "Backend"
        case .scaling: "Scaling"
        case .interview: "Interviews"
        }
    }
}

nonisolated enum TechBlogFeed: String, CaseIterable, Codable, Sendable, Identifiable {
    case top, new
    var id: String { rawValue }
    var title: String { self == .top ? "Top stories" : "Newest stories" }
}

nonisolated struct TechBlogSettings: Codable, Equatable, Sendable {
    var topics: Set<TechBlogTopic> = Set(TechBlogTopic.allCases)
    var feed: TechBlogFeed = .top
    var storyCount = 100
    var freshnessDays = 3
    var minimumScore = 0
    var importLimit = 10

    static let storageKey = "techBlogImportSettings"

    var validated: Self {
        var value = self
        value.storyCount = min(500, max(1, storyCount))
        value.freshnessDays = min(7, max(1, freshnessDays))
        value.minimumScore = min(1000, max(0, minimumScore))
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

nonisolated struct HackerNewsItem: Decodable, Sendable {
    let id: Int
    var type: String? = nil
    var title: String? = nil
    var url: String? = nil
    var score: Int? = nil
    var time: TimeInterval? = nil
    var dead: Bool? = nil
    var deleted: Bool? = nil
}

nonisolated struct TechBlogStory: Sendable {
    let id: Int
    let title: String
    let url: URL
    let score: Int
    let submittedAt: Date
    let topics: Set<TechBlogTopic>
}

nonisolated struct TechBlogDiscoveryResult: Sendable {
    var stories: [TechBlogStory]
    var failedItemCount = 0
}

nonisolated protocol TechBlogDiscovering: Sendable {
    func discover(settings: TechBlogSettings) async throws -> TechBlogDiscoveryResult
}

nonisolated enum TechBlogDiscoveryError: LocalizedError {
    case noTopics, unavailable
    var errorDescription: String? {
        switch self {
        case .noTopics: "Choose at least one topic."
        case .unavailable: "Couldn’t fetch stories from Hacker News. Please try again."
        }
    }
}

/// Fetches only HN metadata. Article extraction remains in the library importer.
nonisolated struct TechBlogDiscovery: TechBlogDiscovering {
    typealias Loader = @Sendable (URL) async throws -> Data
    private let load: Loader
    private let now: @Sendable () -> Date
    private static let baseURL = URL(string: "https://hacker-news.firebaseio.com/v0/")!

    init(load: @escaping Loader = { try await TechBlogDiscovery.fetch($0) }, now: @escaping @Sendable () -> Date = { Date() }) {
        self.load = load
        self.now = now
    }

    static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Pagehum/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TechBlogDiscoveryError.unavailable
        }
        return data
    }

    func discover(settings: TechBlogSettings) async throws -> TechBlogDiscoveryResult {
        let settings = settings.validated
        guard !settings.topics.isEmpty else { throw TechBlogDiscoveryError.noTopics }
        try Task.checkCancellation()
        let data = try await load(Self.baseURL.appendingPathComponent("\(settings.feed.rawValue)stories.json"))
        let ids = try JSONDecoder().decode([Int].self, from: data)
        var seen = Set<Int>()
        let selected = Array(ids.filter { $0 > 0 && seen.insert($0).inserted }.prefix(settings.storyCount))
        let loaded = try await withThrowingTaskGroup(of: HackerNewsItem?.self) { group in
            var iterator = selected.makeIterator()
            func enqueue(_ id: Int) {
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        let data = try await load(Self.baseURL.appendingPathComponent("item/\(id).json"))
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
        if !selected.isEmpty && loaded.0.isEmpty { throw TechBlogDiscoveryError.unavailable }
        return TechBlogDiscoveryResult(
            stories: Self.filter(loaded.0, settings: settings, now: now()),
            failedItemCount: loaded.1
        )
    }

    static func isBlocked(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) else { return true }
        return blockedDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func classify(title: String, url: URL) -> Set<TechBlogTopic> {
        let text = title + " " + (url.absoluteString.removingPercentEncoding ?? url.absoluteString)
        let range = NSRange(text.startIndex..., in: text)
        return Set(patterns.compactMap { topic, expressions in
            expressions.contains { $0.firstMatch(in: text, range: range) != nil } ? topic : nil
        })
    }

    static func filter(_ items: [HackerNewsItem], settings: TechBlogSettings, now: Date) -> [TechBlogStory] {
        let settings = settings.validated
        let cutoff = now.addingTimeInterval(-Double(settings.freshnessDays) * 86400)
        return items.compactMap { item -> TechBlogStory? in
            guard item.type == "story", item.dead != true, item.deleted != true,
                  let title = item.title, !title.isEmpty,
                  let rawURL = item.url, let url = URL(string: rawURL),
                  let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  let host = url.host, !host.isEmpty, !isBlocked(url),
                  let time = item.time, time.isFinite,
                  time >= cutoff.timeIntervalSince1970, time <= now.timeIntervalSince1970,
                  (item.score ?? 0) >= settings.minimumScore else { return nil }
            let topics = classify(title: title, url: url).intersection(settings.topics)
            guard !topics.isEmpty else { return nil }
            return TechBlogStory(id: item.id, title: title, url: url, score: item.score ?? 0,
                                submittedAt: Date(timeIntervalSince1970: time), topics: topics)
        }.sorted {
            if settings.feed == .top && $0.score != $1.score { return $0.score > $1.score }
            if $0.submittedAt != $1.submittedAt { return $0.submittedAt > $1.submittedAt }
            return $0.id < $1.id
        }
    }
}

nonisolated private extension TechBlogDiscovery {
    // Topic expressions and source exclusions ported from the supplied hn-filter script.
    static let patterns: [TechBlogTopic: [NSRegularExpression]] = {
        let source: [TechBlogTopic: [String]] = [
            .ai: [
                #"\bai\b"#,
                #"\bartificial.intelligence\b"#,
                #"\bllm\b"#,
                #"\bgpt[-\s]?\d"#,
                #"\btransformer[s]?\b"#,
                #"\bdeep\s?learning\b"#,
                #"\bmachine\s?learning\b"#,
                #"\bneural\s?net"#,
                #"\blarge\s?language\s?model"#,
                #"\bdiffusion\b"#,
                #"\bfine[- ]?tun"#,
                #"\breinforcement\s?learning\b"#,
                #"\bretrieval.augmented"#,
                #"\bembedding[s]?\b"#,
                #"\bmultimodal\b"#,
                #"\bvector\s?database"#,
                #"\bopen\s?ai\b"#,
                #"\banthrop"#,
                #"\bdeepseek\b"#,
                #"\bgemini\b"#,
                #"\bclaude\b"#,
                #"\bcodex\b"#,
                #"\bqwen\b"#,
                #"\bmistral\b"#,
                #"\bstable\s?diffusion\b"#,
                #"\bmodel[s]?\b.*\btrain"#,
                #"\btrain.*\bmodel[s]?\b"#,
                #"\binference\b"#,
                #"\bpretrain"#,
                #"\bllm\s?agent"#,
                #"\bai\s?agent"#,
                #"\balpha\s?genome\b"#,
                #"\breasoning\s?prefill"#,
            ],
            .backend: [
                #"\bbackend\b"#,
                #"\bserver[- ]?side\b"#,
                #"\bmicroservice"#,
                #"\bdatabase\b"#,
                #"\bpostgres"#,
                #"\bmysql\b"#,
                #"\bredis\b"#,
                #"\bkafka\b"#,
                #"\brabbitmq\b"#,
                #"\bmessage\s?queue"#,
                #"\bcontainer[s]?\b"#,
                #"\bdocker\b"#,
                #"\bkubernetes\b"#,
                #"\bk8s\b"#,
                #"\bgolang\b"#,
                #"\bjvm\b"#,
                #"\bnode\.?js\b"#,
                #"\bgrpc\b"#,
                #"\bgraphql\b"#,
                #"\bnosql\b"#,
                #"\bcaching\b"#,
                #"\bserverless\b"#,
                #"\bdevops\b"#,
                #"\bci[/ ]cd\b"#,
                #"\bnginx\b"#,
                #"\breverse\s?proxy\b"#,
                #"\bobject\s?storage\b"#,
                #"\bdurable\s?object"#,
                #"\breact\s?native\b"#,
                #"\bddos\b"#,
                #"\bversion\s?control\b"#,
                #"\brootless\s?container"#,
                #"\blibzmq\b"#,
                #"\bvsock\b"#,
            ],
            .scaling: [
                #"\bscal(e|ing|ability)\b"#,
                #"\bdistributed\s?system"#,
                #"\bhigh\s?availability\b"#,
                #"\bload\s?balanc"#,
                #"\bsharding\b"#,
                #"\breplication\b"#,
                #"\bthroughput\b"#,
                #"\blatency\b"#,
                #"\brate\s?limit"#,
                #"\bcircuit\s?breaker"#,
                #"\bfault\s?toler"#,
                #"\bresilien"#,
                #"\bsystem\s?design\b"#,
                #"\bcapacity\s?plan"#,
            ],
            .interview: [
                #"\binterview\b"#,
                #"\bcoding\s?(challenge|problem|question)"#,
                #"\bsystem\s?design\b"#,
                #"\balgorithm[s]?\b"#,
                #"\bdata\s?structure"#,
                #"\bleetcode\b"#,
                #"\bhackerrank\b"#,
                #"\binterview\s?prep\b"#,
                #"\bwhiteboard\b"#,
                #"\btechnical\s?(screen|interview|round)"#,
                #"\bpolynomial[s]?\b"#,
                #"\bdynamic\s?programming\b"#,
                #"\bbig[- ]?o\b"#,
                #"\bcard\s?network"#,
            ],
        ]
        return source.mapValues { expressions in
            expressions.map { try! NSRegularExpression(pattern: $0, options: .caseInsensitive) }
        }
    }()

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
