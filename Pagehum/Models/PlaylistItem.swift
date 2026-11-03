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
    // String shares its storage with fullText until edited, so this does not copy the body.
    @Transient private var cachedText: String? = nil
    @Transient private var cachedCharacterCount: Int? = nil
    @Transient private var cachedTextID: String? = nil
    var dateAdded: Date
    var lastPlayed: Date
    var progressPercent: Double
    var lastSentenceIndex: Int
    var playbackTextOffset: Int?
    var status: String = "inProgress"
    var isFavorite: Bool = false

    var librarySource: String {
        if let sourceURL, let host = URL(string: sourceURL)?.host() { return host }
        return sourceType == "pdf" ? String(localized: "PDF document") : String(localized: "Pasted text")
    }

    var libraryProgress: Double {
        status == Status.completed.rawValue ? 1 : min(1, max(0, progressPercent))
    }

    /// Count text once, without sentence tokenization or decoding code payloads.
    /// Derived metadata stays in memory, with no store migration or writes during rendering.
    var libraryCharacterCount: Int {
        invalidateTextCachesIfNeeded()
        if let cachedCharacterCount { return cachedCharacterCount }
        let count = ArticleSegmenter.strippingMarkers(fullText).count
        cachedCharacterCount = count
        return count
    }

    /// Offline status is shown in library cells; hashing must not repeat on every redraw.
    var offlineTextID: String {
        invalidateTextCachesIfNeeded()
        if let cachedTextID { return cachedTextID }
        let id = OfflineAudioRequest.textIdentifier(fullText)
        cachedTextID = id
        return id
    }

    private func invalidateTextCachesIfNeeded() {
        let text = fullText
        if let cachedText {
            // Native strings share their UTF-8 buffer until edited. Check that identity
            // first so unchanged rows never scan the article during a redraw.
            let sharesStorage = cachedText.utf8.withContiguousStorageIfAvailable { cached in
                text.utf8.withContiguousStorageIfAvailable { current in
                    cached.count == current.count && cached.baseAddress == current.baseAddress
                } ?? false
            } ?? false
            // Byte equality also handles replacement strings without confusing canonically
            // equivalent Unicode text whose offline audio hashes are different.
            if sharesStorage || cachedText.utf8.elementsEqual(text.utf8) { return }
        }
        cachedText = text
        cachedCharacterCount = nil
        cachedTextID = nil
    }

    init(title: String, sourceURL: String? = nil, sourceType: String, fullText: String, status: String = Status.inProgress.rawValue) {
        self.title = title
        self.sourceURL = sourceURL
        self.sourceType = sourceType
        // `fullText` may carry ArticleSegmenter code-block markers; strip them so the library row
        // shows prose rather than base64.
        let previewText = ArticleSegmenter.strippingMarkers(fullText)
        self.textPreview = String(previewText.prefix(200))
        self.fullText = fullText
        self.dateAdded = Date()
        self.lastPlayed = Date()
        self.progressPercent = 0
        self.lastSentenceIndex = 0
        self.playbackTextOffset = 0
        self.status = status
        self.cachedText = fullText
        self.cachedCharacterCount = previewText.count
    }
}
