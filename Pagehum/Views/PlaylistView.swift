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
    private let addContent: (() -> Void)?
    private let openReader: (() -> Void)?

    init(viewModel: ReaderModel, addContent: (() -> Void)? = nil, openReader: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.addContent = addContent
        self.openReader = openReader
        queue = viewModel.listeningQueue
    }

    var body: some View {
        let filteredItems = LibraryFilter(query: searchText, favoritesOnly: favoritesOnly).apply(to: allItems)
        let completedItems = filteredItems.filter { $0.status == PlaylistItem.Status.completed.rawValue || $0.progressPercent >= 1 }
        let inProgressItems = filteredItems.filter { item in
            !completedItems.contains(where: { $0.persistentModelID == item.persistentModelID }) &&
            item.status == PlaylistItem.Status.inProgress.rawValue &&
            item.progressPercent < 1
        }
        let unreadItems = filteredItems.filter { item in
            !completedItems.contains(where: { $0.persistentModelID == item.persistentModelID }) &&
            !inProgressItems.contains(where: { $0.persistentModelID == item.persistentModelID })
        }
        let displayOrder = inProgressItems + unreadItems + (selecting ? completedItems : [])
        let selectedItems = displayOrder.filter { selection.contains($0.persistentModelID) }
        let queueableItems = selectedItems.filter { !queue.contains($0.persistentModelID) }
        // The current article stays: its next progress save would touch a deleted model.
        let removableItems = selectedItems.filter { $0.persistentModelID != viewModel.currentPlaylistItemID && !queue.contains($0.persistentModelID) }
        let appending = queue.isActive || (viewModel.progress < 1 && (viewModel.isPlaying || viewModel.isPaused || viewModel.isPreparing))
        let playTitle: LocalizedStringKey = appending
            ? "Add \(queueableItems.count) to queue" : "Play ^[\(queueableItems.count) article](inflect: true)"

        VStack(spacing: 0) {
            LibrarySearchControls(query: $searchText, favoritesOnly: $favoritesOnly)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            if allItems.isEmpty {
                ContentUnavailableView {
                    Label("No articles yet", systemImage: "book.closed")
                } description: {
                    Text("Save a link or open a document to start your library.")
                } actions: {
                    if let addContent {
                        Button("Add an article", action: addContent)
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    }
                }
            } else if filteredItems.isEmpty {
                LibrarySearchEmptyView(query: searchText, favoritesOnly: favoritesOnly) {
                    searchText = ""
                    favoritesOnly = false
                }
            } else {
                List {
                    // 1. In Progress first
                    if !inProgressItems.isEmpty {
                        Section {
                            ForEach(inProgressItems) { item in
                                libraryRow(item)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }
                            .onDelete { offsets in deleteItems(from: inProgressItems, at: offsets) }
                        } header: {
                            Label("In Progress", systemImage: "play.circle")
                        }
                    }

                    // 2. Unread second
                    if !unreadItems.isEmpty {
                        Section {
                            ForEach(unreadItems) { item in
                                libraryRow(item)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }
                            .onDelete { offsets in deleteItems(from: unreadItems, at: offsets) }
                        } header: {
                            Label("Unread", systemImage: "tray")
                        }
                    }

                    // 3. Completed in a summary row which can be clicked to see the list of completed
                    if !completedItems.isEmpty && selecting {
                        Section("Completed") {
                            ForEach(completedItems) { item in libraryRow(item) }
                        }
                    } else if !completedItems.isEmpty {
                        Section {
                            NavigationLink {
                                CompletedArticlesView(viewModel: viewModel, initialSearchText: searchText, openReader: openReader)
                            } label: {
                                CompletedSummaryRow(
                                    completedCount: completedItems.count,
                                    totalCompletedCount: allItems.filter { $0.status == PlaylistItem.Status.completed.rawValue || $0.progressPercent >= 1 }.count,
                                    isFiltered: !searchText.isEmpty || favoritesOnly
                                )
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        } header: {
                            Label("Completed", systemImage: "checkmark.circle")
                        }
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.interactively)
                #else
                .listStyle(.plain)
                #endif
            }
        }
        .navigationTitle("Library")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            if !displayOrder.isEmpty {
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
                            selection = Set(displayOrder.map(\.persistentModelID))
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
                                viewModel.saveLibraryChanges(in: modelContext)
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
                            queue.enqueue(queueableItems)
                            selection = []
                            selecting = false
                            // A new queue opens its first article; show it with the player.
                            if !appending, let first = queueableItems.first { showReader(for: first) }
                        } label: {
                            Text(playTitle).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(queueableItems.isEmpty || viewModel.isLoading)
                    }
                    Button {
                        viewModel.saveAudioOffline(selectedItems)
                        selection = []
                        selecting = false
                    } label: {
                        Label("Save selected audio offline", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedItems.isEmpty || !viewModel.isModelLoaded)
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
            #if os(iOS)
            PhoneReaderView(viewModel: viewModel)
            #else
            if let url = viewModel.content?.source.webURL {
                WebReaderView(viewModel: viewModel, url: url)
            } else {
                ReaderView(viewModel: viewModel)
            }
            #endif
        }
    }

    private func libraryRow(_ item: PlaylistItem) -> some View {
        let queued = queue.contains(item.persistentModelID)
        let selected = selection.contains(item.persistentModelID)
        let isCurrent = viewModel.currentPlaylistItemID == item.persistentModelID
        let isPlaying = isCurrent && (viewModel.isPlaying || viewModel.isPreparing)

        return HStack(alignment: .center, spacing: 4) {
            if selecting {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .padding(.trailing, 8)
                    .accessibilityHidden(true)
            }
            Button {
                if selecting {
                    if selected { selection.remove(item.persistentModelID) } else { selection.insert(item.persistentModelID) }
                } else {
                    open(item)
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    PlaylistRowView(item: item, isPlaying: isPlaying, isInQueue: queued && !selecting)
                    OfflineAudioProgressView(manager: viewModel.offlineAudio, id: viewModel.offlineAudioID(for: item))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selecting && selected ? .isSelected : [])

            if selecting && queued {
                Text("In queue")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            } else if !selecting {
                LibraryFavoriteButton(item: item, compact: true)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                item.isFavorite.toggle()
                viewModel.saveLibraryChanges(in: modelContext)
            } label: {
                Label(item.isFavorite ? "Unstar" : "Star", systemImage: item.isFavorite ? "star.slash" : "star.fill")
            }
            .tint(.yellow)
        }
        .contextMenu {
            OfflineAudioMenuActions(manager: viewModel.offlineAudio, id: viewModel.offlineAudioID(for: item),
                                    canSave: viewModel.isModelLoaded, canRemove: !isPlaying,
                                    save: { viewModel.saveAudioOffline([item]) })
            Divider()
            Button {
                open(item)
            } label: {
                Label(item.progressPercent > 0 ? "Resume" : "Play", systemImage: "play.fill")
            }

            if !queued && item.progressPercent < 1 {
                Button {
                    queue.enqueue([item])
                } label: {
                    Label("Add to Queue", systemImage: "text.badge.plus")
                }
            }

            Button {
                item.isFavorite.toggle()
                viewModel.saveLibraryChanges(in: modelContext)
            } label: {
                Label(item.isFavorite ? "Remove from Starred" : "Star Article", systemImage: item.isFavorite ? "star.slash" : "star")
            }

            Divider()

            if item.status == PlaylistItem.Status.completed.rawValue || item.progressPercent >= 1 {
                Button {
                    item.status = PlaylistItem.Status.inProgress.rawValue
                    item.progressPercent = 0
                    item.lastSentenceIndex = 0
                    item.playbackTextOffset = 0
                    viewModel.saveLibraryChanges(in: modelContext)
                } label: {
                    Label("Mark as Unread", systemImage: "arrow.counterclockwise")
                }
            } else {
                Button {
                    item.status = PlaylistItem.Status.completed.rawValue
                    item.progressPercent = 1.0
                    item.playbackTextOffset = item.fullText.utf16.count
                    viewModel.saveLibraryChanges(in: modelContext)
                } label: {
                    Label("Mark as Completed", systemImage: "checkmark.circle")
                }
            }

            if let urlString = item.sourceURL, let url = URL(string: urlString) {
                ShareLink(item: url) {
                    Label("Share Link", systemImage: "square.and.arrow.up")
                }
            }

            Divider()

            Button(role: .destructive) {
                if item.persistentModelID != viewModel.currentPlaylistItemID {
                    modelContext.delete(item)
                    viewModel.saveLibraryChanges(in: modelContext)
                }
            } label: {
                Label("Delete Article", systemImage: "trash")
            }
            .disabled(item.persistentModelID == viewModel.currentPlaylistItemID)
        }
    }

    private func deleteItems(from sectionItems: [PlaylistItem], at offsets: IndexSet) {
        for index in offsets {
            let item = sectionItems[index]
            if item.persistentModelID != viewModel.currentPlaylistItemID {
                modelContext.delete(item)
            }
        }
        viewModel.saveLibraryChanges(in: modelContext)
    }

    private func open(_ item: PlaylistItem) {
        viewModel.openLibraryItem(item, preservingQueue: viewModel.currentPlaylistItemID == item.persistentModelID)
        showReader(for: item)
    }

    private func showReader(for item: PlaylistItem) {
        if let openReader { openReader() }
        else { selectedItem = item }
    }
}

// MARK: - Completed Summary Row

struct CompletedSummaryRow: View {
    let completedCount: Int
    let totalCompletedCount: Int
    var isFiltered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Completed Articles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if isFiltered && completedCount != totalCompletedCount {
                    Text("\(completedCount) matching (\(totalCompletedCount) total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(completedCount == 1 ? "1 article finished" : "\(completedCount) articles finished")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("\(completedCount)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

// MARK: - Completed Articles View

struct CompletedArticlesView: View {
    @ObservedObject var viewModel: ReaderModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlaylistItem.lastPlayed, order: .reverse) private var allItems: [PlaylistItem]
    @State private var searchText: String
    @State private var favoritesOnly = false
    @State private var selectedItem: PlaylistItem?
    @State private var confirmingClearAll = false
    private let openReader: (() -> Void)?

    init(viewModel: ReaderModel, initialSearchText: String = "", openReader: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.openReader = openReader
        _searchText = State(initialValue: initialSearchText)
    }

    var completedItems: [PlaylistItem] {
        let filtered = LibraryFilter(query: searchText, favoritesOnly: favoritesOnly).apply(to: allItems)
        return filtered.filter { $0.status == PlaylistItem.Status.completed.rawValue || $0.progressPercent >= 1 }
    }

    var body: some View {
        VStack(spacing: 0) {
            if allItems.contains(where: { $0.status == PlaylistItem.Status.completed.rawValue || $0.progressPercent >= 1 }) {
                LibrarySearchControls(query: $searchText, favoritesOnly: $favoritesOnly)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }

            if completedItems.isEmpty {
                ContentUnavailableView(
                    "No Completed Articles",
                    systemImage: "checkmark.circle",
                    description: Text(searchText.isEmpty && !favoritesOnly
                        ? "Articles you finish reading will appear here."
                        : "No completed articles match your filter.")
                )
            } else {
                List {
                    Section {
                        ForEach(completedItems) { item in
                            completedRow(item)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                        .onDelete(perform: deleteCompletedItems)
                    } header: {
                        Text("\(completedItems.count) completed")
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.interactively)
                #else
                .listStyle(.plain)
                #endif
            }
        }
        .navigationTitle("Completed")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !completedItems.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        confirmingClearAll = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Clear all completed")
                    .confirmationDialog(
                        "Clear all completed articles?",
                        isPresented: $confirmingClearAll,
                        titleVisibility: .visible
                    ) {
                        Button("Clear All (\(completedItems.count))", role: .destructive) {
                            for item in completedItems {
                                if item.persistentModelID != viewModel.currentPlaylistItemID {
                                    modelContext.delete(item)
                                }
                            }
                            viewModel.saveLibraryChanges(in: modelContext)
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will remove finished articles from your library.")
                    }
                }
            }
        }
        .navigationDestination(item: $selectedItem) { _ in
            #if os(iOS)
            PhoneReaderView(viewModel: viewModel)
            #else
            if let url = viewModel.content?.source.webURL {
                WebReaderView(viewModel: viewModel, url: url)
            } else {
                ReaderView(viewModel: viewModel)
            }
            #endif
        }
    }

    private func completedRow(_ item: PlaylistItem) -> some View {
        HStack(alignment: .center, spacing: 4) {
            Button {
                open(item)
            } label: {
                PlaylistRowView(
                    item: item,
                    isPlaying: viewModel.currentPlaylistItemID == item.persistentModelID && (viewModel.isPlaying || viewModel.isPreparing)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            LibraryFavoriteButton(item: item, compact: true)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                item.isFavorite.toggle()
                viewModel.saveLibraryChanges(in: modelContext)
            } label: {
                Label(item.isFavorite ? "Unstar" : "Star", systemImage: item.isFavorite ? "star.slash" : "star.fill")
            }
            .tint(.yellow)
        }
        .contextMenu {
            Button {
                open(item)
            } label: {
                Label("Listen Again", systemImage: "play.fill")
            }

            Button {
                item.status = PlaylistItem.Status.inProgress.rawValue
                item.progressPercent = 0
                item.lastSentenceIndex = 0
                item.playbackTextOffset = 0
                viewModel.saveLibraryChanges(in: modelContext)
            } label: {
                Label("Mark as Unread", systemImage: "arrow.counterclockwise")
            }

            Button {
                item.isFavorite.toggle()
                viewModel.saveLibraryChanges(in: modelContext)
            } label: {
                Label(item.isFavorite ? "Remove from Starred" : "Star Article", systemImage: item.isFavorite ? "star.slash" : "star")
            }

            if let urlString = item.sourceURL, let url = URL(string: urlString) {
                ShareLink(item: url) {
                    Label("Share Link", systemImage: "square.and.arrow.up")
                }
            }

            Divider()

            Button(role: .destructive) {
                if item.persistentModelID != viewModel.currentPlaylistItemID {
                    modelContext.delete(item)
                    viewModel.saveLibraryChanges(in: modelContext)
                }
            } label: {
                Label("Delete Article", systemImage: "trash")
            }
            .disabled(item.persistentModelID == viewModel.currentPlaylistItemID)
        }
    }

    private func open(_ item: PlaylistItem) {
        viewModel.openLibraryItem(item, preservingQueue: viewModel.currentPlaylistItemID == item.persistentModelID)
        if let openReader { openReader() }
        else { selectedItem = item }
    }

    private func deleteCompletedItems(at offsets: IndexSet) {
        for index in offsets {
            let item = completedItems[index]
            if item.persistentModelID != viewModel.currentPlaylistItemID {
                modelContext.delete(item)
            }
        }
        viewModel.saveLibraryChanges(in: modelContext)
    }
}

// MARK: - Row

struct PlaylistRowView: View {
    let item: PlaylistItem
    var isPlaying: Bool = false
    var isInQueue: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Source icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(badgeColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: badgeIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(badgeColor)
            }

            // Title + concise metadata
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if isPlaying {
                        Image(systemName: "waveform")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                    }
                }

                HStack(spacing: 5) {
                    Text(item.librarySource)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if isInQueue {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        Label("In queue", systemImage: "text.badge.plus")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if item.progressPercent > 0 && item.progressPercent < 1.0 {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        HStack(spacing: 4) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 32, height: 4)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.accentColor)
                                        .frame(width: 32 * max(0.08, min(1.0, item.progressPercent)), height: 4)
                                }

                            Text("\(Int(item.progressPercent * 100))%")
                                .font(.caption2.monospacedDigit().weight(.medium))
                                .foregroundStyle(Color.accentColor)
                        }
                    } else if item.status == PlaylistItem.Status.queued.rawValue {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        Label("Saved", systemImage: "arrow.down.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    } else if item.progressPercent >= 1.0 || item.status == PlaylistItem.Status.completed.rawValue {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        Label("Completed", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }

                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    let timeDate = (item.progressPercent > 0 || item.status == PlaylistItem.Status.completed.rawValue) ? item.lastPlayed : item.dateAdded
                    Text(timeDate, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        + Text(" ago")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .lineLimit(1)
            }

            Spacer(minLength: 4)
        }
        .padding(.vertical, 3)
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
