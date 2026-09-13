// Modified for Pagehum: unified application and command-line naming.
import Foundation
import SwiftData
import Testing
@testable import Pagehum

@MainActor
struct LegacyPlaybackOffsetMigrationTests {
    @Test
    func resolvesIndicesMarkersEmojiDuplicatesBoundsAndCompletion() {
        let repeated = "😀 Repeat."
        let marker = ArticleSegmenter.marker(for: CodeBlock(language: nil, source: "value"))
        let body = "  \(repeated)\n\n\(marker)\n\n\(repeated)"
        let firstOffset = 2
        let markerOffset = firstOffset + repeated.utf16.count + 2
        let finalProseOffset = markerOffset + marker.utf16.count + 2

        #expect(resolve(body, index: -4) == firstOffset)
        #expect(resolve(body, index: 0) == firstOffset)
        #expect(resolve(body, index: 1) == markerOffset)
        #expect(resolve(body, index: 2) == finalProseOffset)
        #expect(resolve(body, index: 3) == body.utf16.count)
        #expect(resolve(body, index: 99) == body.utf16.count)
        #expect(resolve(body, index: 0, isCompleted: true) == body.utf16.count)
        #expect(resolve("", index: 99) == 0)
    }

    @Test
    func opensCurrentSchemaAndPersistsOffsetsFromStoreWithoutOffsetAttribute() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let storeURL = directory.appending(path: "Legacy.store")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let body = "First.\n\nSecond."
        try writeLegacyStore(at: storeURL, body: body)

        let currentSchema = Schema([PlaylistItem.self, ListeningRecord.self])
        let configuration = ModelConfiguration(
            "MigrationFixture",
            schema: currentSchema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: currentSchema, configurations: configuration)
        let context = container.mainContext
        var items = try context.fetch(FetchDescriptor<PlaylistItem>())

        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.playbackTextOffset == nil })

        LegacyPlaybackOffsetMigration.migrate(
            items: items,
            splitProse: splitParagraphs
        )
        try context.save()
        context.rollback()
        items = try context.fetch(FetchDescriptor<PlaylistItem>())

        let inProgress = try #require(items.first { $0.title == "In progress" })
        let completed = try #require(items.first { $0.title == "Completed" })
        #expect(inProgress.playbackTextOffset == 8)
        #expect(completed.playbackTextOffset == body.utf16.count)
    }

    private func resolve(_ text: String, index: Int, isCompleted: Bool = false) -> Int {
        LegacyPlaybackOffsetMigration.resolve(
            fullText: text,
            legacySentenceIndex: index,
            isCompleted: isCompleted,
            splitProse: splitParagraphs
        )
    }

    private func splitParagraphs(_ text: String) -> [String] {
        text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func writeLegacyStore(at url: URL, body: String) throws {
        let legacySchema = Schema([
            LegacyModels.PlaylistItem.self,
            LegacyModels.ListeningRecord.self,
        ])
        let configuration = ModelConfiguration(
            "MigrationFixture",
            schema: legacySchema,
            url: url,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: legacySchema, configurations: configuration)
        let context = container.mainContext

        let inProgress = LegacyModels.PlaylistItem(
            title: "In progress",
            sourceType: "text",
            fullText: body
        )
        inProgress.lastSentenceIndex = 1
        inProgress.progressPercent = 0.5

        let completed = LegacyModels.PlaylistItem(
            title: "Completed",
            sourceType: "text",
            fullText: body,
            status: PlaylistItem.Status.completed.rawValue
        )
        completed.lastSentenceIndex = 1
        completed.progressPercent = 1

        context.insert(inProgress)
        context.insert(completed)
        try context.save()
    }
}

private enum LegacyModels {
    @Model
    final class PlaylistItem {
        var title: String
        var sourceURL: String?
        var sourceType: String
        var textPreview: String
        var fullText: String
        var dateAdded: Date
        var lastPlayed: Date
        var progressPercent: Double
        var lastSentenceIndex: Int
        var status: String = "inProgress"

        init(
            title: String,
            sourceURL: String? = nil,
            sourceType: String,
            fullText: String,
            status: String = "inProgress"
        ) {
            self.title = title
            self.sourceURL = sourceURL
            self.sourceType = sourceType
            self.textPreview = String(fullText.prefix(200))
            self.fullText = fullText
            self.dateAdded = Date()
            self.lastPlayed = Date()
            self.progressPercent = 0
            self.lastSentenceIndex = 0
            self.status = status
        }
    }

    @Model
    final class ListeningRecord {
        @Attribute(.unique) var dateString: String
        var date: Date
        var secondsListened: Double

        init(date: Date = Date(), secondsListened: Double = 0) {
            self.dateString = "fixture"
            self.date = date
            self.secondsListened = secondsListened
        }
    }
}