import Foundation
import SwiftData
import Testing
@testable import Pagehum

@MainActor
struct LibraryBackupTests {
    private func container() throws -> ModelContainer {
        let schema = Schema([PlaylistItem.self, ListeningRecord.self])
        return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test
    func textOnlyRoundTripRestoresPostsProgressFavoritesAndHistory() throws {
        let source = try container()
        let code = ArticleSegmenter.marker(for: CodeBlock(language: "swift", source: "print(\"hello\")"))
        let item = PlaylistItem(title: "Café 👩🏽‍💻", sourceURL: "https://example.com/post", sourceType: "url",
                                fullText: "First sentence. \(code) Second sentence.")
        item.progressPercent = 0.5
        item.lastSentenceIndex = 1
        item.playbackTextOffset = 16
        item.isFavorite = true
        item.dateAdded = Date(timeIntervalSince1970: 1_700_000_000)
        item.lastPlayed = item.dateAdded.addingTimeInterval(100)
        source.mainContext.insert(item)
        let pdf = PlaylistItem(title: "PDF", sourceURL: "notes.pdf", sourceType: "pdf", fullText: "Extracted PDF text.", status: "completed")
        pdf.progressPercent = 1
        pdf.playbackTextOffset = pdf.fullText.utf16.count
        source.mainContext.insert(pdf)
        source.mainContext.insert(PlaylistItem(title: "Notes", sourceType: "text", fullText: "Pasted text.", status: "queued"))
        let record = ListeningRecord(date: item.dateAdded, secondsListened: 123.75)
        // A day key from another time zone must not be recomputed on import.
        record.dateString = "2023-11-15"
        source.mainContext.insert(record)
        try source.mainContext.save()

        let data = try LibraryBackupStore.snapshot(in: source.mainContext).encoded()
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == ["format", "version", "exportedAt", "articles", "listeningHistory"])
        let backup = try LibraryBackup.decode(data)
        let target = try container()
        let result = try LibraryBackupStore.merge(backup, into: target.mainContext)
        #expect(result.addedArticles == 3)
        // Fetch through a fresh context to verify the import was saved.
        let context = ModelContext(target)
        let restored = try #require(context.fetch(FetchDescriptor<PlaylistItem>()).first { $0.sourceType == "url" })
        #expect(restored.title == item.title)
        #expect(restored.fullText == item.fullText)
        #expect(restored.textPreview == item.textPreview)
        #expect(restored.sourceURL == item.sourceURL)
        #expect(restored.dateAdded == item.dateAdded)
        #expect(restored.lastPlayed == item.lastPlayed)
        #expect(restored.progressPercent == 0.5)
        #expect(restored.lastSentenceIndex == 1)
        #expect(restored.playbackTextOffset == 16)
        #expect(restored.isFavorite)
        let day = try #require(context.fetch(FetchDescriptor<ListeningRecord>()).first)
        #expect(day.secondsListened == 123.75)
        #expect(day.dateString == "2023-11-15")
        #expect(day.date == record.date)
        let statuses = try context.fetch(FetchDescriptor<PlaylistItem>()).map(\.status)
        #expect(Set(statuses) == ["queued", "inProgress", "completed"])
    }

    @Test
    func repeatedImportsKeepLatestPositionAndDoNotDoubleCountHistory() throws {
        let target = try container()
        let local = PlaylistItem(title: "Local", sourceType: "text", fullText: "First sentence. Second sentence.")
        local.lastPlayed = Date(timeIntervalSince1970: 2_000)
        local.progressPercent = 0.1 // A newer restart should win over older completion.
        local.dateAdded = Date(timeIntervalSince1970: 1_000)
        target.mainContext.insert(local)
        let day = ListeningRecord(secondsListened: 80)
        target.mainContext.insert(day)
        var article = LibraryBackupStore.snapshot(local)
        article.title = "Older title"
        article.lastPlayed = Date(timeIntervalSince1970: 1_500)
        article.dateAdded = Date(timeIntervalSince1970: 500)
        article.progressPercent = 1
        article.status = "completed"
        article.isFavorite = true
        var backup = LibraryBackup(exportedAt: Date(), articles: [article], listeningHistory: [
            .init(dateString: day.dateString, date: day.date, secondsListened: 120)
        ])
        _ = try LibraryBackupStore.merge(backup, into: target.mainContext)
        _ = try LibraryBackupStore.merge(backup, into: target.mainContext)
        #expect(try target.mainContext.fetchCount(FetchDescriptor<PlaylistItem>()) == 1)
        #expect(try target.mainContext.fetchCount(FetchDescriptor<ListeningRecord>()) == 1)
        #expect(local.title == "Local")
        #expect(local.progressPercent == 0.1)
        #expect(local.status == "inProgress")
        #expect(local.isFavorite)
        #expect(local.dateAdded == article.dateAdded)
        #expect(day.secondsListened == 120)

        backup.articles[0].lastPlayed = Date(timeIntervalSince1970: 3_000)
        backup.articles[0].progressPercent = 0.75
        backup.articles[0].lastSentenceIndex = 1
        backup.articles[0].playbackTextOffset = 16
        backup.articles[0].status = "inProgress"
        backup.articles[0].isFavorite = false
        backup.listeningHistory[0].secondsListened = 50
        _ = try LibraryBackupStore.merge(backup, into: target.mainContext)
        #expect(local.progressPercent == 0.75)
        #expect(local.lastSentenceIndex == 1)
        #expect(local.playbackTextOffset == 16)
        #expect(local.isFavorite)
        #expect(day.secondsListened == 120)
    }

    @Test
    func changedTextStaysSeparateAndDuplicateEntriesWithinBackupMerge() throws {
        let target = try container()
        let local = PlaylistItem(title: "Saved version", sourceURL: "https://example.com", sourceType: "url", fullText: "Original text.")
        target.mainContext.insert(local)
        var changed = LibraryBackupStore.snapshot(local)
        changed.fullText = "Updated article text."
        let backup = LibraryBackup(exportedAt: Date(), articles: [changed, changed], listeningHistory: [])
        let result = try LibraryBackupStore.merge(backup, into: target.mainContext)
        #expect(result.addedArticles == 1)
        #expect(result.matchedArticles == 1)
        #expect(try target.mainContext.fetchCount(FetchDescriptor<PlaylistItem>()) == 2)
        #expect(local.fullText == "Original text.")
    }

    @Test
    func invalidTailRecordAndUnsupportedVersionsLeaveLibraryUntouched() throws {
        let target = try container()
        let item = PlaylistItem(title: "Existing", sourceType: "text", fullText: "Saved text.")
        target.mainContext.insert(item)
        try target.mainContext.save()
        var article = LibraryBackupStore.snapshot(item)
        article.title = "Must not apply"
        article.lastPlayed = item.lastPlayed.addingTimeInterval(100)
        var invalid = article
        invalid.playbackTextOffset = 9_999
        var backup = LibraryBackup(exportedAt: Date(), articles: [article, invalid], listeningHistory: [])
        #expect(throws: (any Error).self) { try LibraryBackupStore.merge(backup, into: target.mainContext) }
        #expect(item.title == "Existing")
        #expect(!target.mainContext.hasChanges)
        backup.articles = [article]
        backup.version = 2
        #expect(throws: (any Error).self) { try LibraryBackupStore.merge(backup, into: target.mainContext) }
        #expect(item.title == "Existing")
        #expect(throws: (any Error).self) { try LibraryBackup.decode(Data("{\"unrelated\":true}".utf8)) }
    }

    @Test
    func invalidURLsDaysAndNonFiniteTotalsAreRejected() throws {
        let item = PlaylistItem(title: "Article", sourceType: "text", fullText: "Some text.")
        var backup = LibraryBackup(exportedAt: Date(), articles: [LibraryBackupStore.snapshot(item)], listeningHistory: [])
        backup.articles[0].sourceType = "url"
        backup.articles[0].sourceURL = "file:///private/example"
        #expect(throws: (any Error).self) { try backup.validate() }
        backup.articles = []
        backup.listeningHistory = [.init(dateString: "2026-02-30", date: Date(), secondsListened: 10)]
        #expect(throws: (any Error).self) { try backup.validate() }
        backup.listeningHistory[0].dateString = "2026-02-28"
        backup.listeningHistory[0].secondsListened = .infinity
        #expect(throws: (any Error).self) { try backup.validate() }
        backup.listeningHistory[0].secondsListened = -1
        #expect(throws: (any Error).self) { try backup.validate() }
    }

    @Test
    func selectedJSONFileCanBeReadAndMalformedFileIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "backup.json")
        let backup = LibraryBackup(exportedAt: Date(), articles: [], listeningHistory: [])
        try backup.encoded().write(to: url)
        #expect(try LibraryBackup.read(from: url).articles.isEmpty)
        try Data("not a backup".utf8).write(to: url)
        #expect(throws: (any Error).self) { try LibraryBackup.read(from: url) }
    }

    @Test
    func activeReaderFollowsImportedPositionAndExportFlushesCurrentProgress() async throws {
        let target = try container()
        let model = ReaderModel(loadModelOnInit: false)
        model.modelContext = target.mainContext
        await model.loadText("First sentence. Second sentence. Third sentence.")
        model.currentSentenceIndex = 1
        model.progress = 1.0 / 3
        try model.saveForLibraryBackup()
        var backup = try LibraryBackupStore.snapshot(in: target.mainContext)
        #expect(backup.articles[0].lastSentenceIndex == 1)
        #expect(backup.articles[0].playbackTextOffset == 16)
        backup.articles[0].lastPlayed = Date().addingTimeInterval(60)
        backup.articles[0].lastSentenceIndex = 2
        backup.articles[0].playbackTextOffset = 33
        backup.articles[0].progressPercent = 2.0 / 3
        _ = try LibraryBackupStore.merge(backup, into: target.mainContext)
        model.didImportLibraryBackup()
        #expect(model.currentSentenceIndex == 2)
        let restored = try #require(target.mainContext.fetch(FetchDescriptor<PlaylistItem>()).first)
        #expect(restored.playbackTextOffset == 33)
        #expect(restored.lastPlayed == backup.articles[0].lastPlayed)
    }
}
