// Modified for Pagehum: unified application and command-line naming.
#if os(macOS)
import SwiftUI
import SwiftData

struct DesktopLibraryView: View {
    @ObservedObject var viewModel: ReaderModel
    @ObservedObject var queue: ListeningQueue
    var items: [PlaylistItem]
    var openItem: (PlaylistItem) -> Void
    var addContent: () -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var itemsToDelete: [PlaylistItem] = []
    @State private var selection: Set<PersistentIdentifier> = []
    @State private var confirmingRemoval = false
    @State private var selectedCharacters = 0
    @State private var searchText = ""
    @State private var favoritesOnly = false
    @State private var statusFilter: PlaylistItem.Status?
    @State private var sortOrder = [KeyPathComparator(\PlaylistItem.dateAdded, order: .reverse)]

    private var appending: Bool { queue.isActive || (viewModel.progress < 1 && (viewModel.isPlaying || viewModel.isPaused || viewModel.isPreparing)) }

    private func isAlreadyQueued(_ item: PlaylistItem) -> Bool {
        queue.contains(item.persistentModelID) || (appending && item.persistentModelID == viewModel.currentPlaylistItemID)
    }

    var body: some View {
        let filteredItems = LibraryFilter(query: searchText, favoritesOnly: favoritesOnly,
                                          status: statusFilter, sortOrder: sortOrder).apply(to: items)
        let selectedItems = filteredItems.filter { selection.contains($0.persistentModelID) }
        let queueableItems = selectedItems.filter { !isAlreadyQueued($0) }
        let removableItems = selectedItems.filter { $0.persistentModelID != viewModel.currentPlaylistItemID }
        let pendingRemoval = itemsToDelete.filter { $0.persistentModelID != viewModel.currentPlaylistItemID }

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Your library").font(.system(size: 24, weight: .medium))
                    Spacer(minLength: 0)
                    Button {
                        viewModel.saveAudioOffline(selectedItems)
                    } label: {
                        Label("Save audio offline", systemImage: "arrow.down.circle").labelStyle(.iconOnly)
                    }
                    .disabled(selectedItems.isEmpty || !viewModel.isModelLoaded).help("Save selected audio offline")
                    Button {
                        selection = Set(filteredItems.map(\.persistentModelID))
                    } label: {
                        Image(systemName: "checkmark.rectangle.stack").frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .disabled(filteredItems.isEmpty)
                    .help("Select all articles")
                    .accessibilityLabel("Select all articles")
                }
                LibrarySearchControls(query: $searchText, favoritesOnly: $favoritesOnly, compact: true)
                HStack(spacing: 12) {
                    Picker("Status", selection: $statusFilter) {
                        Text("All").tag(PlaylistItem.Status?.none)
                        Text("In progress").tag(PlaylistItem.Status?.some(.inProgress))
                        Text("Saved").tag(PlaylistItem.Status?.some(.queued))
                        Text("Completed").tag(PlaylistItem.Status?.some(.completed))
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    .frame(maxWidth: 380)
                    Spacer(minLength: 0)
                    Text("^[\(filteredItems.count) article](inflect: true)")
                        .font(.caption).foregroundStyle(DesktopStyle.secondary)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 20)

            if items.isEmpty {
                ContentUnavailableView {
                    Label("A place for your next listen", systemImage: "books.vertical")
                } description: { Text("Articles you open or save will appear here.") }
                actions: { Button("Add your first article", action: addContent).buttonStyle(DesktopButtonStyle(primary: true)) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    articleTable(filteredItems, availableWidth: geometry.size.width)
                        .overlay {
                            if filteredItems.isEmpty {
                                ContentUnavailableView {
                                    Label("No matching articles", systemImage: "magnifyingglass")
                                } actions: {
                                    Button("Clear filters") {
                                        searchText = ""
                                        favoritesOnly = false
                                        statusFilter = nil
                                    }
                                }
                            }
                        }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !selectedItems.isEmpty {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(selectedItems.count) selected").font(.callout.weight(.medium))
                        if !queueableItems.isEmpty {
                            Text("\(ListeningQueue.durationLabel(characters: selectedCharacters, speed: viewModel.speed)) at \(DesktopStyle.speedLabel(viewModel.speed))")
                                .font(.caption).foregroundStyle(DesktopStyle.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Button {
                        if let item = selectedItems.first { openItem(item) }
                    } label: {
                        Label("Open article", systemImage: "book").labelStyle(.iconOnly)
                    }
                    .disabled(selectedItems.count != 1).help("Open selected article")
                    Button(role: .destructive) {
                        requestRemoval(selectedItems)
                    } label: {
                        Label("Remove from library", systemImage: "trash").labelStyle(.iconOnly)
                    }
                    .disabled(removableItems.isEmpty).help("Remove selected articles")
                    Button(queueTitle(count: queueableItems.count)) {
                        enqueue(queueableItems)
                    }
                    .buttonStyle(DesktopButtonStyle(primary: true))
                    .disabled(queueableItems.isEmpty || !viewModel.isModelLoaded || viewModel.isLoading)
                    .help(viewModel.isModelLoaded ? "Listen in the displayed sort order" : "Waiting for the voice engine to load")
                    Button { selection = [] } label: {
                        Label("Clear selection", systemImage: "xmark").labelStyle(.iconOnly)
                    }
                    .help("Clear selection")
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(DesktopStyle.panel)
                .overlay(alignment: .top) { Rectangle().fill(DesktopStyle.border).frame(height: 1) }
            }
        }
        .onChange(of: queueableItems.map(\.persistentModelID)) { _, _ in
            selectedCharacters = queueableItems.reduce(0) { $0 + ListeningQueue.remainingCharacters(in: $1) }
        }
        .onChange(of: filteredItems.map(\.persistentModelID)) { _, ids in selection.formIntersection(ids) }
        .confirmationDialog(
            Text(AttributedString(localized: "Remove ^[\(pendingRemoval.count) article](inflect: true) from library?")),
            isPresented: $confirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                for item in pendingRemoval {
                    queue.remove(item.persistentModelID)
                    selection.remove(item.persistentModelID)
                    modelContext.delete(item)
                }
                itemsToDelete = []
            }
            Button("Cancel", role: .cancel) { itemsToDelete = [] }
        } message: {
            if pendingRemoval.count < itemsToDelete.count {
                Text("The current article stays in your library.")
            } else if let item = pendingRemoval.first, pendingRemoval.count == 1 {
                Text(item.title)
            }
        }
    }

    private func articleTable(_ articles: [PlaylistItem], availableWidth: CGFloat) -> some View {
        let sourceWidth = min(140, max(76, availableWidth * 0.16))
        let fixedColumnsAndInsets: CGFloat = 104 + 72 + 60 + 100
        return Table(articles, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Title", value: \PlaylistItem.title) { item in
                HStack(spacing: 8) {
                    Image(systemName: item.sourceType == "url" ? "globe" : "doc.text")
                        .foregroundStyle(DesktopStyle.secondary).frame(width: 16)
                        .accessibilityHidden(true)
                    Text(item.title).fontWeight(.medium).lineLimit(1).help(item.title)
                    if item.persistentModelID == viewModel.currentPlaylistItemID {
                        Image(systemName: "waveform").foregroundStyle(DesktopStyle.accent)
                            .help("Current article").accessibilityLabel("Current article")
                    } else if queue.contains(item.persistentModelID) {
                        Image(systemName: "text.line.first.and.arrowtriangle.forward")
                            .foregroundStyle(DesktopStyle.secondary)
                            .help("In queue").accessibilityLabel("In queue")
                    }
                }
                .frame(height: 32)
            }
            .width(min: 150, ideal: max(150, availableWidth - sourceWidth - fixedColumnsAndInsets))
            TableColumn("Source", value: \PlaylistItem.librarySource) { item in
                Text(item.librarySource).foregroundStyle(DesktopStyle.secondary)
                    .lineLimit(1).help(item.sourceURL ?? item.librarySource)
            }
            .width(min: 76, ideal: sourceWidth, max: 220)
            TableColumn("Progress", value: \PlaylistItem.libraryProgress) { item in
                if item.libraryProgress >= 1 {
                    Label("Completed", systemImage: "checkmark")
                        .foregroundStyle(DesktopStyle.secondary)
                } else if item.libraryProgress > 0 {
                    HStack(spacing: 6) {
                        ProgressView(value: item.libraryProgress).tint(DesktopStyle.accent)
                            .frame(width: 42)
                            .accessibilityHidden(true)
                        Text(item.libraryProgress, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Listening progress")
                    .accessibilityValue(item.libraryProgress.formatted(.percent.precision(.fractionLength(0))))
                } else {
                    Text(item.status == PlaylistItem.Status.queued.rawValue ? "Saved" : "Not started")
                        .foregroundStyle(DesktopStyle.secondary)
                }
            }
            .width(104)
            TableColumn("Added", value: \PlaylistItem.dateAdded) { item in
                Text(item.dateAdded, format: .dateTime.day().month(.abbreviated))
                    .foregroundStyle(DesktopStyle.secondary).lineLimit(1)
                    .help(item.dateAdded.formatted(date: .complete, time: .shortened))
            }
            .width(72)
            TableColumn("Actions") { item in
                HStack(spacing: 0) {
                    LibraryFavoriteButton(item: item, compact: true)
                    Menu {
                        articleActions([item])
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 24, height: 28)
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden)
                    .help("Article options").accessibilityLabel("Options for \(item.title)")
                }
            }
            .width(60)
        }
        .font(.system(size: 13))
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: PersistentIdentifier.self) { identifiers in
            articleActions(articles.filter { identifiers.contains($0.persistentModelID) })
        } primaryAction: { identifiers in
            if identifiers.count == 1, let item = articles.first(where: { identifiers.contains($0.persistentModelID) }) {
                openItem(item)
            }
        }
        .onDeleteCommand {
            requestRemoval(articles.filter { selection.contains($0.persistentModelID) })
        }
        .onExitCommand { selection = [] }
        .accessibilityLabel("Library articles")
    }

    @ViewBuilder private func articleActions(_ articles: [PlaylistItem]) -> some View {
        if let item = articles.first {
            if articles.count == 1 {
                Button("Open article") { openItem(item) }
            }
            let queueableItems = articles.filter { !isAlreadyQueued($0) }
            Button("Save audio offline", systemImage: "arrow.down.circle") { viewModel.saveAudioOffline(articles) }
                .disabled(!viewModel.isModelLoaded)
            Button(queueTitle(count: queueableItems.count)) { enqueue(queueableItems) }
                .disabled(queueableItems.isEmpty || !viewModel.isModelLoaded || viewModel.isLoading)
            Divider()
            Button("Remove from library...", role: .destructive) { requestRemoval(articles) }
                .disabled(articles.allSatisfy { $0.persistentModelID == viewModel.currentPlaylistItemID })
        }
    }

    private func queueTitle(count: Int) -> LocalizedStringKey {
        appending ? "Add \(count) to queue" : "Play ^[\(count) article](inflect: true)"
    }

    private func enqueue(_ articles: [PlaylistItem]) {
        let queueableItems = articles.filter { !isAlreadyQueued($0) }
        guard !queueableItems.isEmpty, viewModel.isModelLoaded, !viewModel.isLoading else { return }
        queue.enqueue(queueableItems)
        selection = []
    }

    private func requestRemoval(_ articles: [PlaylistItem]) {
        guard articles.contains(where: { $0.persistentModelID != viewModel.currentPlaylistItemID }) else { return }
        itemsToDelete = articles
        confirmingRemoval = true
    }
}

struct DesktopArticleRow: View {
    let item: PlaylistItem
    var action: () -> Void
    var isSelected = false
    var trailingLabel: String?
    @State private var hovering = false

    private var progress: Double { min(1, max(0, item.progressPercent)) }
    private var source: String {
        if let value = item.sourceURL, let host = URL(string: value)?.host() { return host }
        return item.sourceType == "pdf" ? "PDF document" : "Pasted text"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: item.sourceType == "url" ? "globe" : "doc.text")
                    .font(.system(size: 18))
                    .foregroundStyle(DesktopStyle.secondary)
                    .frame(width: 40, height: 44)
                    .background(DesktopStyle.border.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title).font(.system(size: 15, weight: .medium)).lineLimit(2)
                    HStack(spacing: 6) {
                        Text(source).lineLimit(1)
                        Text("·")
                        Text(item.dateAdded, format: .dateTime.day().month(.abbreviated))
                    }.font(.caption).foregroundStyle(DesktopStyle.secondary)
                    if progress > 0 && progress < 1 {
                        ProgressView(value: progress).tint(DesktopStyle.accent)
                            .accessibilityLabel("Listening progress")
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    if let trailingLabel {
                        Text(isSelected ? "Selected" : trailingLabel)
                    } else if progress >= 1 {
                        Label("Completed", systemImage: "checkmark.circle")
                    } else {
                        Text(progress > 0 ? "Resume →" : "Open →")
                        if progress > 0 { Text("\(Int(progress * 100))% complete").font(.caption) }
                    }
                }.font(.callout).foregroundStyle(DesktopStyle.accent)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? DesktopStyle.accent.opacity(0.13) : hovering ? DesktopStyle.border : DesktopStyle.panel.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected ? DesktopStyle.accent : DesktopStyle.border))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
#endif
