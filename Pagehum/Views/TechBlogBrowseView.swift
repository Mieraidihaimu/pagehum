import SwiftUI

/// Lets the user choose which Hacker News stories to import.
struct TechBlogBrowseView: View {
    @ObservedObject var viewModel: ReaderModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var sort: TechBlogSort = .newest
    @State private var selection: Set<Int> = []
    @State private var showingSettings = false
    @State private var loadedSettings: TechBlogSettings?
    @State private var previewStory: TechBlogStory?
    @State private var isImportingSelection = false

    private var selectedStories: [TechBlogStory] {
        viewModel.techBlogStories.filter { selection.contains($0.id) && !viewModel.isInLibrary($0) }
    }

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if showingSettings {
                    Button { showingSettings = false } label: {
                        Label("Stories", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                } else {
                    Text("Hacker News").font(.headline)
                    Spacer()
                    settingsButton
                    refreshButton
                }
                Button("Done") { dismiss() }
            }
            .padding(20)
            Divider()
            if showingSettings {
                TechBlogImportSettingsView(viewModel: viewModel)
            } else {
                content
            }
        }
        .frame(minWidth: 620, idealWidth: 760, minHeight: 520, idealHeight: 680)
        .task { await reload() }
        .onChange(of: showingSettings) { _, showing in reloadIfFiltersChanged(showing) }
        .sheet(item: $previewStory) { storyPreview($0) }
        #else
        NavigationStack {
            content
                .navigationTitle("Hacker News")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    ToolbarItemGroup(placement: .primaryAction) {
                        settingsButton
                        refreshButton
                    }
                }
                .navigationDestination(isPresented: $showingSettings) {
                    TechBlogImportSettingsView(viewModel: viewModel)
                }
        }
        .task { await reload() }
        .onChange(of: showingSettings) { _, showing in reloadIfFiltersChanged(showing) }
        .sheet(item: $previewStory) { storyPreview($0) }
        #endif
    }

    private var content: some View {
        let stories = TechBlogDiscovery.browse(viewModel.techBlogStories, query: query, sort: sort)
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Choose your next read").font(.headline)
                    Spacer()
                    Text("^[\(stories.count) story](inflect: true)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                searchField
                Picker("Sort by", selection: $sort) {
                    ForEach(TechBlogSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(16)
            Divider()
            if stories.isEmpty {
                emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(stories, id: \.id) { story in
                            row(story)
                            Divider().padding(.leading, 60)
                        }
                    }
                }
                .disabled(viewModel.isLoading)
            }
            Divider()
            footer.padding(16).background(.bar)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search titles and sites", text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var emptyState: some View {
        if viewModel.isLoading {
            ProgressView("Loading stories…")
        } else if viewModel.techBlogStories.isEmpty && viewModel.errorMessage != nil {
            ContentUnavailableView {
                Label("Couldn’t load stories", systemImage: "exclamationmark.triangle")
            } actions: {
                Button("Retry") { Task { await reload() } }
            }
        } else if viewModel.techBlogStories.isEmpty {
            ContentUnavailableView {
                Label("No matching stories", systemImage: "newspaper")
            } description: {
                Text("Try a longer time window or lower minimums in filters.")
            } actions: {
                Button("Adjust filters") { showingSettings = true }
            }
        } else {
            ContentUnavailableView {
                Label("No results", systemImage: "magnifyingglass")
            } description: {
                Text("Try another title or site name.")
            } actions: {
                Button("Clear search") { query = "" }
            }
        }
    }

    private func row(_ story: TechBlogStory) -> some View {
        let saved = viewModel.isInLibrary(story)
        let selected = !saved && selection.contains(story.id)
        return HStack(alignment: .center, spacing: 8) {
            Button {
                toggleSelection(story)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: saved ? "checkmark.circle" : selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(story.site).lineLimit(1)
                            if saved {
                                Text("Saved").fontWeight(.medium)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        Text(story.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        ViewThatFits(in: .horizontal) {
                            storyMetadata(story)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(story.score.formatted()) points · \(story.comments.formatted()) comments")
                                Text(story.submittedAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .disabled(saved)
            .accessibilityLabel("\(story.title), \(story.site), \(story.score) points, \(story.comments) comments")
            .accessibilityValue(saved ? "Saved" : selected ? "Selected" : "Not selected")
            .accessibilityHint(saved ? "Already in your library" : "Choose this article to import")
            .accessibilityAddTraits(selected ? .isSelected : [])

            Button { previewStory = story } label: {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.body)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel("Preview \(story.title)")
            .help("Preview article")
        }
        .padding(.horizontal, 16)
        .background(selected ? Color.accentColor.opacity(0.06) : Color.clear)
    }

    private func storyMetadata(_ story: TechBlogStory) -> some View {
        HStack(spacing: 12) {
            Label("\(story.score.formatted())", systemImage: "arrow.up")
                .accessibilityLabel("\(story.score) points")
            Label("\(story.comments.formatted())", systemImage: "bubble.right")
                .accessibilityLabel("\(story.comments) comments")
            Text(story.submittedAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
        }
    }

    private func storyPreview(_ story: TechBlogStory) -> some View {
        ArticlePreviewView(title: story.title, url: story.url) {
            HStack(spacing: 12) {
                Link("HN discussion", destination: URL(string: "https://news.ycombinator.com/item?id=\(story.id)")!)
                    .font(.callout)
                Spacer(minLength: 0)
                if viewModel.isInLibrary(story) {
                    Label("Saved to library", systemImage: "checkmark.circle")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Button {
                        toggleSelection(story)
                    } label: {
                        Label(selection.contains(story.id) ? "Selected" : "Select article",
                              systemImage: selection.contains(story.id) ? "checkmark.circle.fill" : "plus.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.isLoading)
                }
            }
        }
    }

    private func toggleSelection(_ story: TechBlogStory) {
        if selection.contains(story.id) { selection.remove(story.id) }
        else { selection.insert(story.id) }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            URLImportStatusView(viewModel: viewModel)
            if let message = viewModel.techBlogMessage {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.orange)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    selectionSummary
                    Spacer(minLength: 0)
                    clearSelectionButton
                    importButton
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        selectionSummary
                        Spacer()
                        clearSelectionButton
                    }
                    importButton.frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var selectionSummary: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(selectedStories.isEmpty ? "Choose articles to import" : "\(selectedStories.count) selected")
                .font(.callout.weight(.semibold))
            let visibleIDs = Set(TechBlogDiscovery.browse(viewModel.techBlogStories, query: query, sort: sort).map(\.id))
            let hiddenCount = selectedStories.filter { !visibleIDs.contains($0.id) }.count
            if hiddenCount > 0 {
                Text("\(hiddenCount) outside this search").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var clearSelectionButton: some View {
        Button("Clear") { selection.removeAll() }
            .disabled(selection.isEmpty || viewModel.isLoading)
    }

    private var importButton: some View {
        Button {
            Task {
                isImportingSelection = true
                defer { isImportingSelection = false }
                await viewModel.importTechBlogStories(selectedStories)
                // Keep failed articles selected so retrying doesn't require finding them again.
                selection = Set(selectedStories.map(\.id))
            }
        } label: {
            if isImportingSelection {
                Label("Importing…", systemImage: "square.and.arrow.down")
            } else if selectedStories.isEmpty {
                Label("Import articles", systemImage: "square.and.arrow.down")
            } else {
                Label("Import ^[\(selectedStories.count) article](inflect: true)", systemImage: "square.and.arrow.down")
            }
        }
        #if os(macOS)
        .buttonStyle(DesktopButtonStyle(primary: true))
        #else
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        #endif
        .disabled(selectedStories.isEmpty || viewModel.isLoading)
    }

    private var refreshButton: some View {
        Button { Task { await reload() } } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .labelStyle(.iconOnly)
        .help("Refresh")
        .disabled(viewModel.isLoading)
    }

    private var settingsButton: some View {
        Button { showingSettings = true } label: {
            Label("Filters", systemImage: "slider.horizontal.3")
        }
        .labelStyle(.iconOnly)
        .help("Filters")
        .disabled(viewModel.isLoading)
    }

    private func reloadIfFiltersChanged(_ showingSettings: Bool) {
        guard !showingSettings, viewModel.techBlogSettings != loadedSettings else { return }
        Task { await reload() }
    }

    private func reload() async {
        selection.removeAll()
        loadedSettings = viewModel.techBlogSettings
        await viewModel.loadTechBlogStories()
    }
}
