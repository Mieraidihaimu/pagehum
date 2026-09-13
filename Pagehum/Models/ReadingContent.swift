import Foundation

enum ContentSource {
    case url(URL)
    case pdf(URL)
    case text(String)

    var webURL: URL? {
        if case .url(let url) = self { return url }
        return nil
    }
}

struct ReadingContent {
    let title: String
    let body: String
    let source: ContentSource
    var byline: String?
    var siteName: String?
    var readerDocument: ReaderDocument?
}
