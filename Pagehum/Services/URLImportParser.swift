import Foundation

nonisolated enum URLImportParser {
    /// Commas and whitespace delimit links. Detection also accepts links in pasted prose.
    static func urls(in text: String) -> [URL] {
        let separated = text.replacingOccurrences(of: ",", with: " ")
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        var seen = Set<String>()
        return detector.matches(in: separated, range: NSRange(separated.startIndex..., in: separated)).compactMap { match in
            guard var url = match.url,
                  let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  let host = url.host, !host.isEmpty else { return nil }
            if let range = Range(match.range, in: separated),
               !separated[range].contains("://"),
               var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                parts.scheme = "https"
                url = parts.url ?? url
            }
            guard seen.insert(key(for: url)).inserted else { return nil }
            return url
        }
    }

    static func key(for url: URL) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = parts.host?.lowercased()
        parts.fragment = nil
        if parts.path.isEmpty { parts.path = "/" }
        if (parts.scheme == "https" && parts.port == 443) || (parts.scheme == "http" && parts.port == 80) { parts.port = nil }
        return parts.string ?? url.absoluteString
    }
}

struct URLImportResult {
    struct Failure: Identifiable {
        let url: URL
        let message: String
        var id: String { url.absoluteString }
    }
    var imported = 0
    var skipped = 0
    var failures: [Failure] = []
    /// The saved article when the request contained one unique URL and succeeded.
    var singleItem: PlaylistItem?

    var summary: String {
        let parts = [
            imported > 0 ? "\(imported) imported" : nil,
            skipped > 0 ? "\(skipped) already saved" : nil,
            failures.isEmpty ? nil : "\(failures.count) failed",
        ].compactMap { $0 }
        return parts.isEmpty ? "Nothing imported" : parts.joined(separator: " · ")
    }
}
