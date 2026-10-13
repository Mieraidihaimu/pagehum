// Modified for Pagehum: unified application and command-line naming.
import Foundation
import SwiftData
import Testing
@testable import Pagehum

@MainActor
struct LibraryFilterTests {
    @Test
    func searchesTitleSourceAndTextBeyondPreviewIgnoringCaseAndAccents() {
        let article = PlaylistItem(title: "Café architecture", sourceURL: "https://example.org/posts/design",
                                   sourceType: "url", fullText: String(repeating: "Introduction. ", count: 30) + "Unusual database details.")
        for query in ["CAFE", "EXAMPLE.ORG", "database", "  architecture\n database  "] {
            #expect(LibraryFilter(query: query).apply(to: [article]).count == 1)
        }
        #expect(!article.textPreview.contains("database"))
        #expect(LibraryFilter(query: "architecture missing").apply(to: [article]).isEmpty)
    }

    @Test
    func combinesFavoritesAndSearchAcrossStatusesWhilePreservingOrder() {
        let items = ["completed", "queued", "inProgress"].map {
            PlaylistItem(title: "Swift article", sourceType: "text", fullText: "Library content", status: $0)
        }
        items[0].isFavorite = true
        items[2].isFavorite = true
        let filter = LibraryFilter(query: "swift", favoritesOnly: true)
        #expect(filter.apply(to: items).map(\.status) == ["completed", "inProgress"])
        #expect(LibraryFilter(query: " \n ").apply(to: items).count == 3)
        #expect(LibraryFilter(query: "missing", favoritesOnly: true).apply(to: items).isEmpty)
        items[0].isFavorite = false
        #expect(filter.apply(to: items).map(\.status) == ["inProgress"])
        #expect(LibraryFilter().apply(to: []).isEmpty)
    }

    @Test
    func doesNotMatchEncodedCodeMarkers() {
        let article = PlaylistItem(title: "Article", sourceType: "text", fullText: "Before \u{E000}hiddenpayload\u{E001} after")
        #expect(LibraryFilter(query: "hiddenpayload").apply(to: [article]).isEmpty)
        #expect(LibraryFilter(query: "before after").apply(to: [article]).count == 1)
    }

    @Test
    func filtersStatusUsingCompletionProgressAsWellAsStoredStatus() {
        let saved = PlaylistItem(title: "Saved", sourceType: "text", fullText: "Text", status: "queued")
        let started = PlaylistItem(title: "Started", sourceType: "text", fullText: "Text")
        let completed = PlaylistItem(title: "Completed", sourceType: "text", fullText: "Text", status: "completed")
        let finished = PlaylistItem(title: "Finished", sourceType: "text", fullText: "Text", status: "queued")
        finished.progressPercent = 1
        let items = [saved, started, completed, finished]

        #expect(LibraryFilter(status: .queued).apply(to: items).map(\.title) == ["Saved"])
        #expect(LibraryFilter(status: .inProgress).apply(to: items).map(\.title) == ["Started"])
        #expect(LibraryFilter(status: .completed).apply(to: items).map(\.title) == ["Completed", "Finished"])
        #expect(LibraryFilter().apply(to: items).count == 4)
    }

    @Test
    func sortsFilteredResultsWithoutChangingTheInputOrder() {
        let older = PlaylistItem(title: "Swift Alpha", sourceType: "text", fullText: "Text", status: "queued")
        let newer = PlaylistItem(title: "Swift Beta", sourceType: "text", fullText: "Text", status: "queued")
        let other = PlaylistItem(title: "Other", sourceType: "text", fullText: "Text")
        older.dateAdded = Date(timeIntervalSince1970: 1)
        newer.dateAdded = Date(timeIntervalSince1970: 2)
        older.isFavorite = true
        newer.isFavorite = true
        let items = [older, other, newer]
        var filter = LibraryFilter(query: "swift", favoritesOnly: true, status: .queued,
                                   sortOrder: [KeyPathComparator(\PlaylistItem.dateAdded, order: .reverse)])

        #expect(filter.apply(to: items).map(\.title) == ["Swift Beta", "Swift Alpha"])
        filter.sortOrder = [KeyPathComparator(\PlaylistItem.title)]
        #expect(filter.apply(to: items).map(\.title) == ["Swift Alpha", "Swift Beta"])
        #expect(items.map(\.title) == ["Swift Alpha", "Other", "Swift Beta"])
    }

    @Test
    func sortsByDisplayedSourceInsteadOfURLScheme() {
        let alpha = PlaylistItem(title: "Alpha", sourceURL: "https://alpha.example/article", sourceType: "url", fullText: "Text")
        let zulu = PlaylistItem(title: "Zulu", sourceURL: "http://zulu.example/article", sourceType: "url", fullText: "Text")
        let filter = LibraryFilter(sortOrder: [KeyPathComparator(\PlaylistItem.librarySource)])

        #expect(alpha.librarySource == "alpha.example")
        #expect(filter.apply(to: [zulu, alpha]).map(\.title) == ["Alpha", "Zulu"])
        #expect(PlaylistItem(title: "PDF", sourceType: "pdf", fullText: "Text").librarySource == String(localized: "PDF document"))
        #expect(PlaylistItem(title: "Text", sourceType: "text", fullText: "Text").librarySource == String(localized: "Pasted text"))
    }

    @Test
    func sortsProgressUsingTheDisplayedCompletionState() {
        let saved = PlaylistItem(title: "Saved", sourceType: "text", fullText: "Text", status: "queued")
        let started = PlaylistItem(title: "Started", sourceType: "text", fullText: "Text")
        let completed = PlaylistItem(title: "Completed", sourceType: "text", fullText: "Text", status: "completed")
        saved.progressPercent = -0.1
        started.progressPercent = 0.5
        let filter = LibraryFilter(sortOrder: [KeyPathComparator(\PlaylistItem.libraryProgress)])

        #expect(saved.libraryProgress == 0)
        #expect(completed.libraryProgress == 1)
        #expect(filter.apply(to: [completed, saved, started]).map(\.title) == ["Saved", "Started", "Completed"])
        started.progressPercent = 1.1
        #expect(started.libraryProgress == 1)
    }

    @Test
    func favoritesDefaultToFalseAndPersistAcrossStoreReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(url: directory.appendingPathComponent("library.store"))

        func saveFavorite(_ favorite: Bool) throws {
            let container = try ModelContainer(for: PlaylistItem.self, configurations: configuration)
            let context = ModelContext(container)
            let item: PlaylistItem
            if let saved = try context.fetch(FetchDescriptor<PlaylistItem>()).first {
                item = saved
            } else {
                item = PlaylistItem(title: "Saved article", sourceType: "text", fullText: "Keep this article.")
                #expect(!item.isFavorite)
                context.insert(item)
            }
            item.isFavorite = favorite
            try context.save()
        }

        func readFavorite() throws -> Bool {
            let container = try ModelContainer(for: PlaylistItem.self, configurations: configuration)
            let context = ModelContext(container)
            let item = try #require(context.fetch(FetchDescriptor<PlaylistItem>()).first)
            #expect(item.fullText == "Keep this article.")
            return item.isFavorite
        }

        try saveFavorite(true)
        #expect(try readFavorite())
        try saveFavorite(false)
        #expect(try !readFavorite())
    }
}
