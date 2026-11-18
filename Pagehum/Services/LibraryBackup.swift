import CryptoKit
import Foundation
import SwiftData

/// A portable, versioned text-only backup. Audio, model assets and device preferences
/// deliberately have no representation in this format.
nonisolated struct LibraryBackup: Codable, Sendable {
    var format = "pagehum-library"
    var version = 1
    var exportedAt: Date
    var articles: [Article]
    var listeningHistory: [HistoryDay]

    struct Article: Codable, Sendable {
        var title: String
        var sourceURL: String?
        var sourceType: String
        var fullText: String
        var dateAdded: Date
        var lastPlayed: Date
        var progressPercent: Double
        var lastSentenceIndex: Int
        var playbackTextOffset: Int?
        var status: String
        var isFavorite: Bool

        /// Match across installations without changing the existing SwiftData schema.
        /// Different versions of an article's text stay separate so offsets remain valid.
        var identity: String {
            let fields: [String?] = [sourceType, sourceURL, fullText]
            let data = try! JSONEncoder().encode(fields)
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }

    struct HistoryDay: Codable, Sendable {
        var dateString: String
        var date: Date
        var secondsListened: Double
    }

    static let maximumFileSize = 50 * 1_024 * 1_024

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumFileSize else { throw BackupError.tooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumFileSize else { throw BackupError.tooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let backup: Self
        do { backup = try decoder.decode(Self.self, from: data) }
        catch { throw BackupError.invalidFile }
        try backup.validate()
        return backup
    }

    /// Coordinated access supports files selected from iCloud Drive and other providers.
    static func read(from url: URL) throws -> Self {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<Self, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readableURL in
            result = Result {
                let size = try readableURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= maximumFileSize else { throw BackupError.tooLarge }
                return try decode(Data(contentsOf: readableURL))
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw BackupError.invalidFile }
        return try result.get()
    }

    func validate() throws {
        guard format == "pagehum-library" else { throw BackupError.invalidFile }
        guard version == 1 else { throw BackupError.unsupportedVersion }
        guard articles.count <= 20_000, listeningHistory.count <= 100_000 else { throw BackupError.tooLarge }
        guard Self.validDate(exportedAt) else { throw BackupError.invalidFile }
        for article in articles {
            guard ["url", "pdf", "text"].contains(article.sourceType),
                  ["queued", "inProgress", "completed"].contains(article.status),
                  article.progressPercent.isFinite, (0...1).contains(article.progressPercent),
                  article.lastSentenceIndex >= 0, article.lastSentenceIndex <= article.fullText.utf16.count,
                  Self.validDate(article.dateAdded), Self.validDate(article.lastPlayed)
            else { throw BackupError.invalidFile }
            if let offset = article.playbackTextOffset,
               !(0...article.fullText.utf16.count).contains(offset) { throw BackupError.invalidFile }
            if article.sourceType == "url" {
                guard let source = article.sourceURL, let url = URL(string: source),
                      ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                      url.host != nil else { throw BackupError.invalidFile }
            }
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        for day in listeningHistory {
            guard day.dateString.count == 10,
                  let date = formatter.date(from: day.dateString), formatter.string(from: date) == day.dateString,
                  Self.validDate(day.date), day.secondsListened.isFinite, day.secondsListened >= 0
            else { throw BackupError.invalidFile }
        }
    }

    private static func validDate(_ date: Date) -> Bool {
        let value = date.timeIntervalSince1970
        return value.isFinite && (-62_135_596_800...253_402_300_799).contains(value)
    }

    enum BackupError: LocalizedError {
        case invalidFile, unsupportedVersion, tooLarge, unsavedChanges

        var errorDescription: String? {
            switch self {
            case .invalidFile: "This is not a valid Pagehum library backup. Your library has not been changed."
            case .unsupportedVersion: "This backup needs a newer version of Pagehum. Update the app before importing it."
            case .tooLarge: "This backup exceeds the supported limit of 50 MB or contains too many records."
            case .unsavedChanges: "Your latest library changes could not be saved. Retry saving before transferring your library."
            }
        }
    }
}

@MainActor
enum LibraryBackupStore {
    static func snapshot(in context: ModelContext) throws -> LibraryBackup {
        let articles = try context.fetch(FetchDescriptor<PlaylistItem>(sortBy: [SortDescriptor(\.dateAdded)]))
        let history = try context.fetch(FetchDescriptor<ListeningRecord>(sortBy: [SortDescriptor(\.dateString)]))
        return LibraryBackup(exportedAt: Date(), articles: articles.map(snapshot), listeningHistory: history.map {
            .init(dateString: $0.dateString, date: $0.date, secondsListened: $0.secondsListened)
        })
    }

    static func snapshot(_ item: PlaylistItem) -> LibraryBackup.Article {
        .init(title: item.title, sourceURL: item.sourceURL, sourceType: item.sourceType, fullText: item.fullText,
              dateAdded: item.dateAdded, lastPlayed: item.lastPlayed, progressPercent: item.progressPercent,
              lastSentenceIndex: item.lastSentenceIndex, playbackTextOffset: item.playbackTextOffset,
              status: item.status, isFavorite: item.isFavorite)
    }

    struct ImportResult {
        var addedArticles = 0
        var matchedArticles = 0
        var historyDays = 0
    }

    /// Validate everything before writing, then save once. Preserve all existing articles.
    /// Daily totals use max rather than addition because backups can overlap.
    static func merge(_ backup: LibraryBackup, into context: ModelContext) throws -> ImportResult {
        try backup.validate()
        // Establish a saved baseline so rollback cannot discard unrelated edits.
        try context.save()
        let existing = try context.fetch(FetchDescriptor<PlaylistItem>())
        var articles: [String: PlaylistItem] = [:]
        for item in existing.sorted(by: { $0.lastPlayed < $1.lastPlayed }) {
            articles[snapshot(item).identity] = item
        }
        var history = Dictionary(try context.fetch(FetchDescriptor<ListeningRecord>()).map { ($0.dateString, $0) },
                                 uniquingKeysWith: { first, _ in first })
        var result = ImportResult()
        do {
            for article in backup.articles {
                let key = article.identity
                if let item = articles[key] {
                    if article.lastPlayed > item.lastPlayed { apply(article, to: item) }
                    item.dateAdded = min(item.dateAdded, article.dateAdded)
                    item.isFavorite = item.isFavorite || article.isFavorite
                    result.matchedArticles += 1
                } else {
                    let item = PlaylistItem(title: article.title, sourceURL: article.sourceURL,
                                            sourceType: article.sourceType, fullText: article.fullText)
                    apply(article, to: item)
                    item.dateAdded = article.dateAdded
                    item.isFavorite = article.isFavorite
                    context.insert(item)
                    articles[key] = item
                    result.addedArticles += 1
                }
            }
            for day in backup.listeningHistory {
                if let record = history[day.dateString] {
                    record.secondsListened = max(record.secondsListened, day.secondsListened)
                } else {
                    let record = ListeningRecord(date: day.date, secondsListened: day.secondsListened)
                    // Preserve the original day key, including when transferring across time zones.
                    record.dateString = day.dateString
                    record.date = day.date
                    context.insert(record)
                    history[day.dateString] = record
                }
            }
            result.historyDays = Set(backup.listeningHistory.map(\.dateString)).count
            try context.save()
            return result
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func apply(_ article: LibraryBackup.Article, to item: PlaylistItem) {
        item.title = article.title
        item.lastPlayed = article.lastPlayed
        item.progressPercent = article.progressPercent
        item.lastSentenceIndex = article.lastSentenceIndex
        item.playbackTextOffset = article.playbackTextOffset
        item.status = article.status
    }
}
