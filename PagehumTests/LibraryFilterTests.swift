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
