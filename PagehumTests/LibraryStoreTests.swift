import Foundation
import SwiftData
import Testing
@testable import Pagehum

@MainActor
struct LibraryStoreTests {
    private enum Failure: Error { case unavailable }

    @Test
    func failedStoreStaysUnavailableUntilRetryOpensTheOriginalStore() throws {
        let container = try ModelContainer(for: PlaylistItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let item = PlaylistItem(title: "Existing article", sourceType: "text", fullText: "Saved content.")
        container.mainContext.insert(item)
        try container.mainContext.save()
        var attempts = 0
        let store = LibraryStore {
            attempts += 1
            if attempts == 1 { throw Failure.unavailable }
            return container
        }
        #expect(store.container == nil)
        #expect(store.errorMessage != nil)
        store.retry()
        #expect(store.container === container)
        #expect(store.errorMessage == nil)
        #expect(try store.container?.mainContext.fetch(FetchDescriptor<PlaylistItem>()).first?.title == "Existing article")
        store.retry()
        #expect(attempts == 2)
    }

    @Test
    func repeatedOpenFailuresNeverCreateAnEmptyTemporaryLibrary() {
        var attempts = 0
        let store = LibraryStore { attempts += 1; throw Failure.unavailable }
        store.retry()
        #expect(attempts == 2)
        #expect(store.container == nil)
        #expect(store.errorMessage != nil)
    }

    @Test
    func savedLibraryAndResumePositionSurviveReopeningDiskStore() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([PlaylistItem.self, ListeningRecord.self])
        let configuration = ModelConfiguration(schema: schema, url: directory.appending(path: "library.store"))
        let first = try ModelContainer(for: schema, configurations: configuration)
        let item = PlaylistItem(title: "Durable article", sourceType: "text", fullText: "First sentence. Second sentence.")
        item.playbackTextOffset = 16
        item.isFavorite = true
        first.mainContext.insert(item)
        let model = ReaderModel(loadModelOnInit: false)
        model.modelContext = first.mainContext
        #expect(model.saveLibraryChanges())

        let reopened = try ModelContainer(for: schema, configurations: configuration)
        let saved = try #require(reopened.mainContext.fetch(FetchDescriptor<PlaylistItem>()).first)
        #expect(saved.title == item.title)
        #expect(saved.playbackTextOffset == 16)
        #expect(saved.isFavorite)
        #expect(model.librarySaveError == nil)
    }
}
