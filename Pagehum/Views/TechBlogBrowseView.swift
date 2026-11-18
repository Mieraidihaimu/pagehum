import SwiftUI

/// Lets the user choose which tech articles to import.
struct TechBlogBrowseView: View {
    @ObservedObject var viewModel: ReaderModel
    var openReader: (() -> Void)? = nil
    var openLibrary: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var sort: TechBlogSort = .newest
    @State private var selection: Set<TechBlogStory.ID> = []
    @State private var showingSettings = false
    @State private var loadedSettings: TechBlogSettings?
    @State private var previewStory: TechBlogStory?
    @State private var isImportingSelection = false
    @FocusState private var isSearching: Bool

    private var source: TechBlogSource { viewModel.techBlogSettings.source }
    private var showsCommunitySort: Bool { source != .blogFeeds }
    private var visibleStories: [TechBlogStory] {
        guard loadedSettings?.source == source else { return [] }
        return TechBlogDiscovery.browse(viewModel.techBlogStories, query: query, sort: showsCommunitySort ? sort : .newest)
    }
    private var selectedStories: [TechBlogStory] {
        guard loadedSettings?.source == source else { return [] }
        return viewModel.techBlogStories.filter { selection.contains($0.id) && !viewModel.isInLibrary($0) }
    }

    var body: some View {
        platformBody
            .task { await reload() }
            .onChange(of: showingSettings) { _, showing in reloadIfFiltersChanged(showing) }
            .onChange(of: source) { _, _ in reloadIfFiltersChanged(showingSettings) }
            .onChange(of: viewModel.isImportBusy) { _, busy in
                if !busy { reloadIfFiltersChanged(showingSettings) }
            }
            .sheet(item: $previewStory) { storyPreview($0) }
            .appTheme()
    }

    private var platformBody: some View {
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
                    Text("Tech blogs").font(.headline)
                    Spacer()
                    settingsButton
                    refreshButton
                }
                Button("Done") { dismiss() }
            }
            .padding(20)
            Divider()
            if showingSettings {
                TechBlogImportSettingsView(viewModel: viewModel, openReader: finishOpening)
            } else {
                content
            }
        }
        .frame(minWidth: 620, idealWidth: 760, minHeight: 520, idealHeight: 680)
        #else
        NavigationStack {
            content
                .navigationTitle("Tech blogs")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    ToolbarItemGroup(placement: .primaryAction) {
                        settingsButton
                        refreshButton
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { isSearching = false }
                    }
                }
                .navigationDestination(isPresented: $showingSettings) {
                    TechBlogImportSettingsView(viewModel: viewModel, openReader: finishOpening, openLibrary: finishImport)
                }
        }
        #endif
    }

    private var content: some View {
        let stories = visibleStories
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                ThemeSegmentedPicker(title: "Source", options: TechBlogSource.allCases,
                                     selection: $viewModel.techBlogSettings.source) { source in
                    Text(source.title)
                }
                .disabled(viewModel.isImportBusy)
                searchField
                if showsCommunitySort {
                    ThemeSegmentedPicker(title: "Sort by", options: TechBlogSort.allCases, selection: $sort) {
                        Text($0.title)
                    }
                }
                Text("^[\(stories.count) story](inflect: true)")
                    .font(.caption).foregroundStyle(AppTheme.textSecondary)
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
                #if os(iOS)
                .scrollDismissesKeyboard(.interactively)
                #endif
                .disabled(viewModel.isImportBusy)
            }
            Divider()
            footer.padding(16).background(AppTheme.surface)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.textSecondary)
            TextField("Search titles and sites", text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($isSearching)
                .onSubmit { isSearching = false }
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                #endif
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(10)
        .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var emptyState: some View {
        if viewModel.isImportBusy || loadedSettings?.source != source {
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
                Text(showsCommunitySort
                     ? "Try a longer time window or lower minimums in filters."
                     : "Refresh the blog feeds or choose another source.")
            } actions: {
                if showsCommunitySort {
                    Button("Adjust filters") { showingSettings = true }
                } else {
                    Button("Refresh") { Task { await reload() } }
                }
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
                        .foregroundStyle(selected ? AppTheme.accentPrimary : AppTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(story.site).lineLimit(1)
                            if saved {
                                Text("Saved").fontWeight(.medium)
                                    .foregroundStyle(AppTheme.accentPrimary)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(AppTheme.accentPrimarySubtle, in: Capsule())
                            }
                        }
                        .font(.caption).foregroundStyle(AppTheme.textSecondary)
                        Text(story.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(AppTheme.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        ViewThatFits(in: .horizontal) {
                            storyMetadata(story)
                            VStack(alignment: .leading, spacing: 4) {
                                if let score = story.score, let comments = story.comments {
                                    Text("\(score.formatted()) points · \(comments.formatted()) comments")
                                }
                                Text(story.date, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                            }
                        }
                        .font(.caption).foregroundStyle(AppTheme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .disabled(saved)
            .accessibilityLabel(storyAccessibilityLabel(story))
            .accessibilityValue(saved ? "Saved" : selected ? "Selected" : "Not selected")
            .accessibilityHint(saved ? "Already in your library" : "Choose this article to import")
            .accessibilityAddTraits(selected ? .isSelected : [])

            Button { previewStory = story } label: {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.body)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.accentPrimarySubtle, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.accentPrimary)
            .accessibilityLabel("Preview \(story.title)")
            .help("Preview article")
        }
        .padding(.horizontal, 16)
        .background(selected ? AppTheme.accentPrimarySubtle : Color.clear)
    }

    private func storyMetadata(_ story: TechBlogStory) -> some View {
        HStack(spacing: 12) {
            if let score = story.score, let comments = story.comments {
                Label("\(score.formatted())", systemImage: "arrow.up")
                    .accessibilityLabel("\(score) points")
                Label("\(comments.formatted())", systemImage: "bubble.right")
                    .accessibilityLabel("\(comments) comments")
            }
            Text(story.date, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
        }
    }

    private func storyAccessibilityLabel(_ story: TechBlogStory) -> Text {
        if let score = story.score, let comments = story.comments {
            return Text("\(story.title), \(story.site), \(score) points, \(comments) comments")
        }
        return Text("\(story.title), \(story.site)")
    }

    private func storyPreview(_ story: TechBlogStory) -> some View {
        ArticlePreviewView(title: story.title, url: story.url) {
            HStack(spacing: 12) {
                if let discussionURL = story.discussionURL {
                    Link("Discussion", destination: discussionURL)
                        .font(.callout)
                }
                Spacer(minLength: 0)
                if viewModel.isInLibrary(story) {
                    Label("Saved to library", systemImage: "checkmark.circle")
                        .font(.callout).foregroundStyle(AppTheme.textSecondary)
                } else {
                    Button {
                        toggleSelection(story)
                    } label: {
                        Label(selection.contains(story.id) ? "Selected" : "Select article",
                              systemImage: selection.contains(story.id) ? "checkmark.circle.fill" : "plus.circle")
                    }
                    .buttonStyle(ThemeButtonStyle())
                    .controlSize(.large)
                    .disabled(viewModel.isImportBusy)
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
            URLImportStatusView(viewModel: viewModel, scope: .all, openReader: finishOpening, openLibrary: finishImport)
            if let message = viewModel.techBlogMessage {
                Text(message).font(.callout).foregroundStyle(AppTheme.textSecondary)
            }
            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(AppTheme.warning)
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
            let visibleIDs = Set(visibleStories.map(\.id))
            let hiddenCount = selectedStories.filter { !visibleIDs.contains($0.id) }.count
            if hiddenCount > 0 {
                Text("\(hiddenCount) outside this search").font(.caption).foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private var clearSelectionButton: some View {
        Button("Clear") { selection.removeAll() }
            .disabled(selection.isEmpty || viewModel.isImportBusy)
    }

    private var importButton: some View {
        Button {
            Task {
                isImportingSelection = true
                defer { isImportingSelection = false }
                await viewModel.importTechBlogStories(selectedStories)
                // Keep failed articles selected so retrying doesn't require finding them again.
                selection = Set(selectedStories.map(\.id))
                if let result = viewModel.importResult, result.singleItem != nil, result.failures.isEmpty {
                    finishImport?()
                }
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
        .buttonStyle(ThemeButtonStyle())
        .controlSize(.large)
        #endif
        .disabled(selectedStories.isEmpty || viewModel.isImportBusy)
    }

    private var finishOpening: (() -> Void)? {
        guard let openReader else { return nil }
        return {
            dismiss()
            openReader()
        }
    }

    private var finishImport: (() -> Void)? {
        guard let openLibrary else { return nil }
        return {
            dismiss()
            openLibrary()
        }
    }

    private var refreshButton: some View {
        Button { Task { await reload() } } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .labelStyle(.iconOnly)
        .help("Refresh")
        .disabled(viewModel.isImportBusy)
    }

    private var settingsButton: some View {
        Button { showingSettings = true } label: {
            Label("Filters", systemImage: "slider.horizontal.3")
        }
        .labelStyle(.iconOnly)
        .help("Filters")
        .disabled(viewModel.isImportBusy)
    }

    private func reloadIfFiltersChanged(_ showingSettings: Bool) {
        guard !showingSettings, !viewModel.isImportBusy, viewModel.techBlogSettings != loadedSettings else { return }
        Task { await reload() }
    }

    private func reload() async {
        guard !viewModel.isImportBusy else { return }
        selection.removeAll()
        loadedSettings = viewModel.techBlogSettings
        await viewModel.loadTechBlogStories()
    }
}
