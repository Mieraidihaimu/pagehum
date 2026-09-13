import Foundation
import SwiftData

@Model
final class PlaylistItem {
    enum Status: String {
        case queued, inProgress, completed
    }

    var title: String
    var sourceURL: String?
    var sourceType: String
    var textPreview: String
    var fullText: String
    var dateAdded: Date
    var lastPlayed: Date
    var progressPercent: Double
    var lastSentenceIndex: Int
    var playbackTextOffset: Int?
    var status: String = "inProgress"
    var isFavorite: Bool = false

    init(title: String, sourceURL: String? = nil, sourceType: String, fullText: String, status: String = Status.inProgress.rawValue) {
        self.title = title
        self.sourceURL = sourceURL
        self.sourceType = sourceType
        // `fullText` may carry ArticleSegmenter code-block markers; strip them so the library row
        // shows prose rather than base64.
        self.textPreview = String(ArticleSegmenter.strippingMarkers(fullText).prefix(200))
        self.fullText = fullText
        self.dateAdded = Date()
        self.lastPlayed = Date()
        self.progressPercent = 0
        self.lastSentenceIndex = 0
        self.playbackTextOffset = 0
        self.status = status
    }
}
