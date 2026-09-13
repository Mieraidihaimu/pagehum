// Modified for Pagehum: unified application and command-line naming.
import SwiftUI
import SwiftData

struct PlaylistView: View {

    @ObservedObject var viewModel: ReaderModel
    @Query(sort: \PlaylistItem.dateAdded, order: .reverse) private var allItems: [PlaylistItem]
    @Environment(\.modelContext) private var modelContext
    @State private var selectedItem: PlaylistItem?
    @State private var searchText = ""
    @State private var favoritesOnly = false

    var body: some View {
        let filteredItems = LibraryFilter(query: searchText, favoritesOnly: favoritesOnly).apply(to: allItems)
        let queuedItems = filteredItems.filter { $0.status == PlaylistItem.Status.queued.rawValue && $0.progressPercent < 1 }
        let inProgressItems = filteredItems.filter { $0.status == PlaylistItem.Status.inProgress.rawValue && $0.progressPercent < 1 }
        let completedItems = filteredItems.filter { $0.status == PlaylistItem.Status.completed.rawValue || $0.progressPercent >= 1 }

        VStack(spacing: 0) {
            LibrarySearchControls(query: $searchText, favoritesOnly: $favoritesOnly)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            if allItems.isEmpty {
                ContentUnavailableView(
                    "No Articles Yet",
                    systemImage: "book.closed",
                    description: Text("Articles you save or read will appear here.")
                )
            } else if filteredItems.isEmpty {
                LibrarySearchEmptyView(query: searchText, favoritesOnly: favoritesOnly) {
                    searchText = ""
                    favoritesOnly = false
                }
            } else {
                List {
                    if !queuedItems.isEmpty {
                        Section {
                            ForEach(queuedItems) { item in
                                libraryRow(item)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .listRowSeparator(.hidden)
                            }
                            .onDelete { offsets in deleteItems(from: queuedItems, at: offsets) }
                        } header: {
                            Label("Reading Queue", systemImage: "bookmark.fill")
                        }
                    }

                    if !inProgressItems.isEmpty {
                        Section {
                            ForEach(inProgressItems) { item in
                                libraryRow(item)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .listRowSeparator(.hidden)
                            }
                            .onDelete { offsets in deleteItems(from: inProgressItems, at: offsets) }
                        } header: {
                            Label("In Progress", systemImage: "play.circle")
                        }
                    }

                    if !completedItems.isEmpty {
                        Section {
                            ForEach(completedItems) { item in
                                libraryRow(item)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .listRowSeparator(.hidden)
                            }
                            .onDelete { offsets in deleteItems(from: completedItems, at: offsets) }
                        } header: {
                            Label("Completed", systemImage: "checkmark.circle")
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Library")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .navigationDestination(item: $selectedItem) { _ in
            if let url = viewModel.content?.source.webURL {
                WebReaderView(viewModel: viewModel, url: url)
            } else {
                ReaderView(viewModel: viewModel)
            }
        }
    }

    private func libraryRow(_ item: PlaylistItem) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Button {
                selectedItem = item
                reloadItem(item)
            } label: {
                PlaylistRowView(item: item)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            LibraryFavoriteButton(item: item)
        }
    }

    private func deleteItems(from sectionItems: [PlaylistItem], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(sectionItems[index])
        }
    }

    private func reloadItem(_ item: PlaylistItem) {
        item.lastPlayed = Date()
        if item.status == PlaylistItem.Status.queued.rawValue {
            item.status = PlaylistItem.Status.inProgress.rawValue
        }
        try? modelContext.save()
        viewModel.stop()

        let source: ContentSource
        if item.sourceType == "url", let urlString = item.sourceURL, let url = URL(string: urlString) {
            source = .url(url)
        } else {
            source = .text(item.fullText)
        }

        viewModel.content = ReadingContent(
            title: item.title,
            body: item.fullText,
            source: source
        )
        viewModel.currentPlaylistItemID = item.persistentModelID
        viewModel.prepareTextPublic(
            item.fullText,
            resumeAt: item.lastSentenceIndex,
            textOffset: item.playbackTextOffset
        )
    }
}

// MARK: - Row

struct PlaylistRowView: View {
    let item: PlaylistItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(badgeColor.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: badgeIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(badgeColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text(item.lastPlayed, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            + Text(" ago")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        if item.status == PlaylistItem.Status.queued.rawValue {
                            Label("Saved offline", systemImage: "arrow.down.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                }

                Spacer(minLength: 0)

                if item.progressPercent >= 1.0 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.body)
                }
            }

            Text(item.textPreview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.leading, 48)

            if item.progressPercent > 0 && item.progressPercent < 1.0 {
                HStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary).frame(height: 3)
                            Capsule().fill(Color.accentColor).frame(width: geo.size.width * item.progressPercent, height: 3)
                        }
                    }
                    .frame(height: 3)

                    Text("\(Int(item.progressPercent * 100))%")
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 32, alignment: .trailing)
                }
                .padding(.leading, 48)
            }
        }
        .padding(.vertical, 4)
    }

    private var badgeIcon: String {
        switch item.sourceType {
        case "url": return "globe"
        case "pdf": return "doc.richtext"
        default: return "text.alignleft"
        }
    }

    private var badgeColor: Color {
        switch item.sourceType {
        case "url": return .blue
        case "pdf": return .red
        default: return .orange
        }
    }
}
