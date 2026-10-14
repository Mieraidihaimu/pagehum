#if os(macOS)
import AppKit
import SwiftData
import SwiftUI
import Testing
@testable import Pagehum

@MainActor
@Suite(.serialized)
struct DesktopLibraryViewTests {
    @Test(arguments: [584.0, 1000.0])
    func tableKeepsRowsCompactAndActionsVisible(width: Double) async throws {
        let container = try ModelContainer(for: PlaylistItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = ReaderModel(loadModelOnInit: false)
        defer { model.cleanup() }
        let items = (0..<60).map { index in
            let item = PlaylistItem(
                title: String(format: "Article %02d: Building reliable applications with long, descriptive titles", index),
                sourceURL: "https://engineering.example.org/articles/\(index)",
                sourceType: "url", fullText: "Sample article text.",
                status: index % 3 == 0 ? "inProgress" : index % 3 == 1 ? "queued" : "completed"
            )
            item.dateAdded = Date().addingTimeInterval(-Double(index) * 86_400)
            item.progressPercent = index % 3 == 0 ? 0.2 : index % 3 == 1 ? 0 : 1
            item.isFavorite = index % 4 == 0
            container.mainContext.insert(item)
            return item
        }
        try container.mainContext.save()
        model.modelContext = container.mainContext
        let view = DesktopLibraryView(viewModel: model, queue: model.listeningQueue, items: items,
                                      openItem: { _ in }, addContent: {})
            .modelContainer(container)
            .background(DesktopStyle.canvas)
            .foregroundStyle(DesktopStyle.text)
            .tint(DesktopStyle.accent)
        let hostingView = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 520),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: width < 600 ? .darkAqua : .aqua)
        window.contentView = hostingView
        defer { window.close() }
        hostingView.layoutSubtreeIfNeeded()
        await Task.yield()
        hostingView.layoutSubtreeIfNeeded()

        let table = try #require(findTable(in: hostingView))
        #expect(table.numberOfRows == items.count)
        #expect(table.tableColumns.count == 5)
        #expect(table.allowsMultipleSelection)
        #expect(table.rect(ofRow: 0).height <= 40)
        #expect(table.tableColumns.prefix(4).allSatisfy { $0.sortDescriptorPrototype != nil })
        #expect(table.rect(ofColumn: 4).maxX <= table.visibleRect.maxX + 1)

        table.selectRowIndexes(IndexSet([0, 1]), byExtendingSelection: false)
        await Task.yield()
        hostingView.layoutSubtreeIfNeeded()
        #expect(table.selectedRowIndexes == IndexSet([0, 1]))

        let bitmap = try #require(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let image = try #require(bitmap.representation(using: .png, properties: [:]))
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("pagehum-library-table-\(Int(width)).png")
        try image.write(to: destination)
        print("Library preview: \(destination.path)")
    }

    private func findTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for child in view.subviews {
            if let table = findTable(in: child) { return table }
        }
        return nil
    }
}
#endif