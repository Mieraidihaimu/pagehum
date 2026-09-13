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
    @State private var itemToDelete: PlaylistItem?
    @State private var selecting = false
    @State private var selection: Set<PersistentIdentifier> = []
    @State private var selectedCharacters = 0
    @State private var searchText = ""
    @State private var favoritesOnly = false

    private var appending: Bool { queue.isActive || (viewModel.progress < 1 && (viewModel.isPlaying || viewModel.isPaused || viewModel.isPreparing)) }

    private func isAlreadyQueued(_ item: PlaylistItem) -> Bool {
        queue.contains(item.persistentModelID) || (appending && item.persistentModelID == viewModel.currentPlaylistItemID)
    }

    var body: some View {
        let filteredItems = LibraryFilter(query: searchText, favoritesOnly: favoritesOnly).apply(to: items)
        let inProgress = filteredItems.filter { $0.status == "inProgress" && $0.progressPercent < 1 }
        let saved = filteredItems.filter { $0.status == "queued" && $0.progressPercent < 1 }
        let completed = filteredItems.filter { $0.status == "completed" || $0.progressPercent >= 1 }
        let displayOrder = inProgress + saved + completed
        let selectedItems = displayOrder.filter { selection.contains($0.persistentModelID) && !isAlreadyQueued($0) }

        DesktopPage {
            HStack(alignment: .top, spacing: 16) {
                DesktopHeading(title: "Your library", subtitle: selecting ? "Choose articles to listen to, one after another." : "Good reads, ready when you are.")
                Spacer(minLength: 0)
                if !items.isEmpty {
                    Button(selecting ? "Cancel selection" : "Select articles") {
                        selecting.toggle()
                        selection = []
                    }.buttonStyle(DesktopButtonStyle())
                }
            }
            LibrarySearchControls(query: $searchText, favoritesOnly: $favoritesOnly)
                .padding(.bottom, 24)
            if items.isEmpty {
                ContentUnavailableView {
                    Label("A place for your next listen", systemImage: "books.vertical")
                } description: { Text("Articles you open or save will appear here.") }
                actions: { Button("Add your first article", action: addContent).buttonStyle(DesktopButtonStyle(primary: true)) }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else if filteredItems.isEmpty {
                LibrarySearchEmptyView(query: searchText, favoritesOnly: favoritesOnly) {
                    searchText = ""
                    favoritesOnly = false
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                section("In progress", items: inProgress)
                section("Saved for later", items: saved)
                section("Completed", items: completed)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selecting {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(selectedItems.count) selected").font(.headline)
                        Text(selectedItems.isEmpty ? "Select one or more articles" : "\(ListeningQueue.durationLabel(characters: selectedCharacters, speed: viewModel.speed)) at \(DesktopStyle.speedLabel(viewModel.speed)) · Library order")
                            .font(.caption).foregroundStyle(DesktopStyle.secondary)
                    }
                    Spacer(minLength: 0)
                    Button("Select all") { selection = Set(displayOrder.filter { !isAlreadyQueued($0) }.map(\.persistentModelID)) }
                        .buttonStyle(DesktopButtonStyle())
                    Button(appending ? "Add \(selectedItems.count) to queue" : "Play \(selectedItems.count) articles") {
                        queue.enqueue(selectedItems)
                        selection = []
                        selecting = false
                    }
                    .buttonStyle(DesktopButtonStyle(primary: true))
                    .disabled(selectedItems.isEmpty || !viewModel.isModelLoaded || viewModel.isLoading)
                    .help(viewModel.isModelLoaded ? "Listen in the displayed Library order" : "Waiting for the voice engine to load")
                }
                .padding(20).background(DesktopStyle.panel)
                .overlay(alignment: .top) { Rectangle().fill(DesktopStyle.border).frame(height: 1) }
            }
        }
        .onChange(of: selectedItems.map(\.persistentModelID)) { _, _ in
            selectedCharacters = selectedItems.reduce(0) { $0 + ListeningQueue.remainingCharacters(in: $1) }
        }
        .onChange(of: displayOrder.map(\.persistentModelID)) { _, ids in selection.formIntersection(ids) }
        .onChange(of: queue.upcoming.map(\.id) + [queue.current?.id].compactMap { $0 }) { _, ids in
            selection.subtract(ids)
        }
        .confirmationDialog("Remove from library?", isPresented: Binding(
            get: { itemToDelete != nil }, set: { if !$0 { itemToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Remove article", role: .destructive) {
                if let itemToDelete {
                    queue.remove(itemToDelete.persistentModelID)
                    selection.remove(itemToDelete.persistentModelID)
                    modelContext.delete(itemToDelete)
                }
                itemToDelete = nil
            }
            Button("Cancel", role: .cancel) { itemToDelete = nil }
        } message: { Text(itemToDelete?.title ?? "") }
    }

    @ViewBuilder private func section(_ title: String, items: [PlaylistItem]) -> some View {
        if !items.isEmpty {
            Text(title).font(.callout).foregroundStyle(DesktopStyle.secondary).padding(.bottom, 12)
            LazyVStack(spacing: 10) {
                ForEach(items) { item in
                    HStack(spacing: 4) {
                        if selecting {
                            Toggle("Select \(item.title)", isOn: Binding(
                                get: { selection.contains(item.persistentModelID) },
                                set: { selected in
                                    if selected { selection.insert(item.persistentModelID) }
                                    else { selection.remove(item.persistentModelID) }
                                }
                            ))
                            .labelsHidden().toggleStyle(.checkbox)
                            .disabled(isAlreadyQueued(item)).padding(.trailing, 8)
                        }
                        DesktopArticleRow(item: item, action: {
                            if selecting {
                                if selection.contains(item.persistentModelID) { selection.remove(item.persistentModelID) }
                                else { selection.insert(item.persistentModelID) }
                            } else { openItem(item) }
                        }, isSelected: selection.contains(item.persistentModelID), trailingLabel: isAlreadyQueued(item) ? "In queue" : selecting ? "Select" : nil)
                        .disabled(selecting && isAlreadyQueued(item))
                        LibraryFavoriteButton(item: item)
                        if !selecting {
                        Menu {
                            Button("Remove from library…", role: .destructive) { itemToDelete = item }
                                .disabled(item.persistentModelID == viewModel.currentPlaylistItemID)
                        } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden)
                        .frame(width: 28).help("Article options")
                        .accessibilityLabel("Options for \(item.title)")
                        }
                    }
                }
            }.padding(.bottom, 28)
        }
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
