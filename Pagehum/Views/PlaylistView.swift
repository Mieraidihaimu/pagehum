// Modified for Pagehum: unified application and command-line naming.
import SwiftUI
import SwiftData

struct PlaylistView: View {

    @ObservedObject var viewModel: ReaderModel
    @ObservedObject private var queue: ListeningQueue
    @Query(sort: \PlaylistItem.dateAdded, order: .reverse) private var allItems: [PlaylistItem]
    @Environment(\.modelContext) private var modelContext
    @State private var selectedItem: PlaylistItem?
    @State private var searchText = ""
    @State private var favoritesOnly = false
    @State private var selecting = false
    @State private var selection: Set<PersistentIdentifier> = []
    @State private var confirmingRemoval = false

    init(viewModel: ReaderModel) {
        self.viewModel = viewModel
        queue = viewModel.listeningQueue
    }

    var body: some View {
        let filteredItems = LibraryFilter(query: searchText, favoritesOnly: favoritesOnly).apply(to: allItems)
        let queuedItems = filteredItems.filter { $0.status == PlaylistItem.Status.queued.rawValue && $0.progressPercent < 1 }
        let inProgressItems = filteredItems.filter { $0.status == PlaylistItem.Status.inProgress.rawValue && $0.progressPercent < 1 }
        let completedItems = filteredItems.filter { $0.status == PlaylistItem.Status.completed.rawValue || $0.progressPercent >= 1 }
        let displayOrder = queuedItems + inProgressItems + completedItems
        let selectedItems = displayOrder.filter { selection.contains($0.persistentModelID) && !queue.contains($0.persistentModelID) }
        // The current article stays: its next progress save would touch a deleted model.
        let removableItems = selectedItems.filter { $0.persistentModelID != viewModel.currentPlaylistItemID }
        let appending = queue.isActive || (viewModel.progress < 1 && (viewModel.isPlaying || viewModel.isPaused || viewModel.isPreparing))
        let playTitle: LocalizedStringKey = appending
            ? "Add \(selectedItems.count) to queue" : "Play ^[\(selectedItems.count) article](inflect: true)"

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
        .toolbar {
            if !allItems.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(selecting ? "Cancel" : "Select") {
                        selecting.toggle()
                        selection = []
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selecting {
                VStack(spacing: 10) {
                    HStack {
                        Text("\(selectedItems.count) selected").font(.headline)
                        Spacer()
                        Button("Select all") {
                            selection = Set(displayOrder.filter { !queue.contains($0.persistentModelID) }.map(\.persistentModelID))
                        }
                    }
                    HStack(spacing: 12) {
                        Button(role: .destructive) {
                            confirmingRemoval = true
                        } label: {
                            Label("Remove from library", systemImage: "trash").labelStyle(.iconOnly)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(removableItems.isEmpty)
                        .confirmationDialog(
                            Text(AttributedString(localized: "Remove ^[\(removableItems.count) article](inflect: true) from library?")),
                            isPresented: $confirmingRemoval,
                            titleVisibility: .visible
                        ) {
                            Button("Remove", role: .destructive) {
                                for item in removableItems { modelContext.delete(item) }
                                selection = []
                                selecting = false
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            if removableItems.count < selectedItems.count {
                                Text("The current article stays in your library.")
                            }
                        }
                        Button {
                            queue.enqueue(selectedItems)
                            selection = []
                            selecting = false
                            // A new queue opens its first article; show it with the player.
                            if !appending { selectedItem = selectedItems.first }
                        } label: {
                            Text(playTitle).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(selectedItems.isEmpty || !viewModel.isModelLoaded || viewModel.isLoading)
                    }
                    if !viewModel.isModelLoaded {
                        Text("Waiting for the voice engine to load")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .background(.bar)
            }
        }
        .navigationDestination(item: $selectedItem) { _ in
            if let url = viewModel.content?.source.webURL {
                WebReaderView(viewModel: viewModel, url: url)
            } else {
                ReaderView(viewModel: viewModel)
            }
        }
    }

    private func libraryRow(_ item: PlaylistItem) -> some View {
        let queued = queue.contains(item.persistentModelID)
        let selected = selection.contains(item.persistentModelID)
        return HStack(alignment: .top, spacing: 4) {
            if selecting {
                Image(systemName: queued ? "checkmark.circle" : selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .padding(.top, 8).padding(.trailing, 8)
                    .accessibilityHidden(true)
            }
            Button {
                if selecting {
                    guard !queued else { return }
                    if selected { selection.remove(item.persistentModelID) } else { selection.insert(item.persistentModelID) }
                } else {
                    open(item)
                }
            } label: {
                PlaylistRowView(item: item)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selecting && selected ? .isSelected : [])
            if selecting && queued {
                Text("In queue").font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            } else if !selecting {
                LibraryFavoriteButton(item: item)
            }
        }
    }

    private func deleteItems(from sectionItems: [PlaylistItem], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(sectionItems[index])
        }
    }

    private func open(_ item: PlaylistItem) {
        // Viewing the current article keeps its queue intact, matching the Mac library.
        viewModel.openLibraryItem(item, preservingQueue: viewModel.currentPlaylistItemID == item.persistentModelID)
        selectedItem = item
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
