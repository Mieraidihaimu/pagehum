import Foundation

/// Shared search semantics for the phone and desktop libraries. Every word must match,
/// but words can appear in different fields and in any order.
struct LibraryFilter {
    var query = ""
    var favoritesOnly = false

    func apply(to items: [PlaylistItem]) -> [PlaylistItem] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return items.filter { item in
            guard !favoritesOnly || item.isFavorite else { return false }
            guard !terms.isEmpty else { return true }
            let fields = [item.title, item.sourceURL ?? "", ArticleSegmenter.strippingMarkers(item.fullText)]
            return terms.allSatisfy { term in
                fields.contains { field in
                    field.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], locale: .current) != nil
                }
            }
        }
    }
}
