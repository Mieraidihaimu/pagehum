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
    @State private var unreadExpanded = true
    @State private var inProgressExpanded = true
    @State private var completedExpanded = true
    @State private var olderExpanded = false
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
        let filter = LibraryFilter(query: searchText, favoritesOnly: favoritesOnly)
        let filteredItems = filter.apply(to: allItems)
        // Completed articles already have a summary row when browsing the library.
        let inlineItems = selecting ? filteredItems : filteredItems.filter { $0.libraryProgress < 1 }
        let (currentItems, olderItems) = filter.groupByAge(inlineItems)
        let completedItems = (selecting ? currentItems : filteredItems).filter { $0.libraryProgress >= 1 }
        let inProgressItems = currentItems.filter { item in
            item.status == PlaylistItem.Status.inProgress.rawValue &&
            item.libraryProgress < 1
        }
        let unreadItems = currentItems.filter { item in
            item.status != PlaylistItem.Status.inProgress.rawValue &&
            item.libraryProgress < 1
        }
        let displayOrder = (unreadExpanded ? unreadItems : []) + (inProgressExpanded ? inProgressItems : [])
            + (selecting && completedExpanded ? completedItems : []) + (olderExpanded ? olderItems : [])
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
                            .buttonStyle(ThemeButtonStyle()).controlSize(.large)
                    }
                }
            } else if filteredItems.isEmpty {
                LibrarySearchEmptyView(query: searchText, favoritesOnly: favoritesOnly) {
                    searchText = ""
                    favoritesOnly = false
                }
            } else {
                List {
                    if !unreadItems.isEmpty {
                        librarySection("Unread", systemImage: "tray", count: unreadItems.count,
                                       isExpanded: $unreadExpanded) {
                            ForEach(unreadItems) { item in
                                libraryRow(item)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }
                            .onDelete { offsets in deleteItems(from: unreadItems, at: offsets) }
                        }
                    }

                    if !inProgressItems.isEmpty {
                        librarySection("In Progress", systemImage: "play.circle", count: inProgressItems.count,
                                       isExpanded: $inProgressExpanded) {
                            ForEach(inProgressItems) { item in
                                libraryRow(item)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }
                            .onDelete { offsets in deleteItems(from: inProgressItems, at: offsets) }
                        }
                    }

                    if !completedItems.isEmpty {
                        librarySection("Completed", systemImage: "checkmark.circle", count: completedItems.count,
                                       isExpanded: $completedExpanded) {
                            if selecting {
                                ForEach(completedItems) { item in libraryRow(item) }
                            } else {
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
                            }
                        }
                    }

                    if !olderItems.isEmpty {
                        librarySection("Older articles", systemImage: "clock", count: olderItems.count,
                                       isExpanded: $olderExpanded) {
                            ForEach(olderItems) { item in
                                libraryRow(item)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }
                            .onDelete { offsets in deleteItems(from: olderItems, at: offsets) }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(AppTheme.canvas)
                #if os(iOS)
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.interactively)
                #else
                .listStyle(.plain)
                #endif
            }
        }
        .background(AppTheme.canvas)
        .navigationTitle("Library")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(AppTheme.canvas, for: .navigationBar)
        #endif
        .toolbar {
            if selecting || !filteredItems.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(selecting ? "Cancel" : "Select") {
                        selecting.toggle()
                        selection = []
                    }
                }
            }
        }
        .onChange(of: displayOrder.map(\.persistentModelID)) { _, ids in selection.formIntersection(ids) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selecting {
                VStack(spacing: 10) {
                    HStack {
                        Text("\(selectedItems.count) selected").font(.headline)
                        Spacer()
                        Button("Select all") {
                            selection = Set(displayOrder.map(\.persistentModelID))
                        }
                        .disabled(displayOrder.isEmpty)
                    }
                    HStack(spacing: 12) {
                        Button(role: .destructive) {
                            confirmingRemoval = true
                        } label: {
                            Label("Remove from library", systemImage: "trash").labelStyle(.iconOnly)
                        }
                        .buttonStyle(ThemeButtonStyle(primary: false))
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
                        .buttonStyle(ThemeButtonStyle())
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
                    .buttonStyle(ThemeButtonStyle(primary: false))
                    .disabled(selectedItems.isEmpty || !viewModel.isModelLoaded)
                    if !viewModel.isModelLoaded {
                        Text("Waiting for the voice engine to load")
                            .font(.caption).foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .padding(16)
                .background(AppTheme.surface)
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

    private func librarySection<Content: View>(
        _ title: LocalizedStringKey, systemImage: String, count: Int,
        isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            if isExpanded.wrappedValue { content() }
        } header: {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack {
                    Label(title, systemImage: systemImage)
                    Spacer()
                    Text(count, format: .number).monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : -90))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(isExpanded.wrappedValue ? Text("Expanded") : Text("Collapsed"))
            .accessibilityHint(isExpanded.wrappedValue ? Text("Collapse section") : Text("Expand section"))
        }
        .listRowBackground(AppTheme.surface)
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
                    .foregroundStyle(selected ? AppTheme.accentPrimary : AppTheme.textSecondary)
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
                    PlaylistRowView(item: item, isPlaying: isPlaying, isInQueue: queued && !selecting, speed: viewModel.speed)
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
                    .foregroundStyle(AppTheme.accentPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.accentPrimarySubtle, in: Capsule())
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
            .tint(AppTheme.cta)
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
                    .fill(AppTheme.accentPrimarySubtle)
                    .frame(width: 32, height: 32)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.success)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Completed Articles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                if isFiltered && completedCount != totalCompletedCount {
                    Text("\(completedCount) matching (\(totalCompletedCount) total)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    Text(completedCount == 1 ? "1 article finished" : "\(completedCount) articles finished")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            Spacer()

            Text("\(completedCount)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.accentPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(AppTheme.accentPrimarySubtle, in: Capsule())
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
                    .listRowBackground(AppTheme.surface)
                }
                .scrollContentBackground(.hidden)
                .background(AppTheme.canvas)
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
                    isPlaying: viewModel.currentPlaylistItemID == item.persistentModelID && (viewModel.isPlaying || viewModel.isPreparing),
                    speed: viewModel.speed
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
            .tint(AppTheme.cta)
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
    var speed: Float = 1
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        #if os(iOS)
        phoneRow
        #else
        desktopRow
        #endif
    }

    #if os(iOS)
    private var phoneRow: some View {
        HStack(alignment: .top, spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.accentPrimarySubtle)
                        .frame(width: 36, height: 36)
                    Image(systemName: badgeIcon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(badgeColor)
                }
                .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text(item.librarySource)
                        .lineLimit(1)
                    if isPlaying {
                        Image(systemName: "waveform")
                            .foregroundStyle(AppTheme.accentPrimary)
                            .accessibilityLabel("Playing")
                    }
                }
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        LibraryDurationLabel(item: item, speed: speed)
                        listeningStatus
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        LibraryDurationLabel(item: item, speed: speed)
                        listeningStatus
                    }
                }

                if isInQueue {
                    Label("In queue", systemImage: "text.badge.plus")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private var listeningStatus: some View {
        if item.progressPercent >= 1 || item.status == PlaylistItem.Status.completed.rawValue {
            Label("Completed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.success)
                .font(.caption)
                .fixedSize()
        } else if item.progressPercent > 0 {
            Text("\(Int(item.progressPercent * 100))% complete")
                .foregroundStyle(AppTheme.accentPrimary)
                .font(.caption.monospacedDigit())
                .fixedSize()
        }
    }
    #endif

    private var desktopRow: some View {
        HStack(alignment: .center, spacing: 12) {
            // Source icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.accentPrimarySubtle)
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
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    if isPlaying {
                        Image(systemName: "waveform")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.accentPrimary)
                    }
                }

                HStack(spacing: 5) {
                    Text(item.librarySource)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if isInQueue {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textMuted)

                        Label("In queue", systemImage: "text.badge.plus")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    if item.progressPercent > 0 && item.progressPercent < 1.0 {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textMuted)

                        HStack(spacing: 4) {
                            Capsule()
                                .fill(AppTheme.borderSubtle)
                                .frame(width: 32, height: 4)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(AppTheme.accentPrimaryFill)
                                        .frame(width: 32 * max(0.08, min(1.0, item.progressPercent)), height: 4)
                                }

                            Text("\(Int(item.progressPercent * 100))%")
                                .font(.caption2.monospacedDigit().weight(.medium))
                                .foregroundStyle(AppTheme.accentPrimary)
                        }
                    } else if item.status == PlaylistItem.Status.queued.rawValue {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textMuted)

                        Label("Saved", systemImage: "arrow.down.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.success)
                    } else if item.progressPercent >= 1.0 || item.status == PlaylistItem.Status.completed.rawValue {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textMuted)

                        Label("Completed", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.success)
                    }

                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textMuted)

                    let timeDate = (item.progressPercent > 0 || item.status == PlaylistItem.Status.completed.rawValue) ? item.lastPlayed : item.dateAdded
                    Text(timeDate, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textMuted)
                        + Text(" ago")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textMuted)
                }
                .lineLimit(1)
            }

            Spacer(minLength: 4)
            LibraryDurationLabel(item: item, speed: speed)
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
        AppTheme.accentPrimary
    }
}
