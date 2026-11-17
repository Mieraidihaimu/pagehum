import Foundation

nonisolated enum TechBlogSyndication {
    static let feeds = [
        URL(string: "https://github.blog/engineering/feed/")!,
        URL(string: "https://blog.cloudflare.com/tag/engineering/rss")!,
        URL(string: "https://jvns.ca/atom.xml")!,
        URL(string: "https://martinfowler.com/feed.atom")!,
    ]

    static func stories(from data: Data, feedURL: URL, now: Date) throws -> [TechBlogStory] {
        let parser = XMLParser(data: data)
        let feed = FeedParser()
        parser.delegate = feed
        parser.shouldProcessNamespaces = true
        guard parser.parse(), feed.isFeed else { throw URLError(.cannotParseResponse) }

        let iso = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let rfc = DateFormatter()
        rfc.locale = Locale(identifier: "en_US_POSIX")
        rfc.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

        let stories = feed.entries.compactMap { entry -> TechBlogStory? in
            guard let title = entry["title"], !title.isEmpty,
                  let link = entry["link"], let url = TechBlogDiscovery.articleURL(link, relativeTo: feedURL),
                  let timestamp = entry["published"] ?? entry["pubDate"] ?? entry["date"] ?? entry["updated"],
                  let date = iso.date(from: timestamp) ?? fractional.date(from: timestamp) ?? rfc.date(from: timestamp),
                  date <= now else { return nil }
            return TechBlogStory(id: URLImportParser.key(for: url), title: title, url: url, date: date)
        }
        let newest = TechBlogDiscovery.browse(stories, query: "", sort: .newest)
        return Array(TechBlogDiscovery.unsaved(newest, savedKeys: []).prefix(5))
    }
}

nonisolated private final class FeedParser: NSObject, XMLParserDelegate {
    private static let textFields: Set<String> = ["title", "link", "published", "pubDate", "date", "updated"]
    private var depth = 0
    private var entryDepth: Int?
    private var entry: [String: String] = [:]
    private var field: String?
    private var value = ""
    private(set) var isFeed = false
    private(set) var entries: [[String: String]] = []

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        depth += 1
        if depth == 1 { isFeed = name == "rss" || name == "feed" }
        if entryDepth == nil, (name == "item" || name == "entry") {
            entryDepth = depth
            entry = [:]
        }
        guard let entryDepth, depth == entryDepth + 1, Self.textFields.contains(name) else { return }
        if name == "link", let href = attributes["href"] {
            if attributes["rel"] == nil || attributes["rel"] == "alternate" {
                entry["link"] = entry["link"] ?? href.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else {
            field = name
            value = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if field != nil { value += string }
    }

    func parser(_ parser: XMLParser, foundCDATA data: Data) {
        if let string = String(data: data, encoding: .utf8) { self.parser(parser, foundCharacters: string) }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        defer { depth -= 1 }
        if let entryDepth, depth == entryDepth + 1, let field {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { entry[field] = text }
            self.field = nil
        }
        if depth == entryDepth {
            entries.append(entry)
            entryDepth = nil
        }
    }
}
