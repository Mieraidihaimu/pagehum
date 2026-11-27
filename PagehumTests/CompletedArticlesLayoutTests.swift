#if os(iOS)
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import Pagehum

@MainActor
struct CompletedArticlesLayoutTests {
    @Test
    func completedRowFitsCompactHeightAtStandardTextSize() throws {
        let schema = Schema([PlaylistItem.self, ListeningRecord.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let item = PlaylistItem(
            title: "How Modern Browsers Render Complex Layouts at 120Hz",
            sourceURL: "https://example.com/article",
            sourceType: "web",
            fullText: String(repeating: "Word ", count: 1200),
            status: PlaylistItem.Status.completed.rawValue
        )
        item.progressPercent = 1.0
        container.mainContext.insert(item)
        try container.mainContext.save()

        let row = PlaylistRowView(item: item, speed: 1)
            .environment(\.dynamicTypeSize, .large)
        let host = UIHostingController(rootView: row)
        host.safeAreaRegions = []
        let size = host.sizeThatFits(in: CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude))
        #expect(size.width <= 300)
        #expect(size.height <= 110)
    }
}
#endif
