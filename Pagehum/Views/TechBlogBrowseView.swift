import SwiftUI

/// Lets the user choose which Hacker News stories to import, starting from the one-tap picks.
struct TechBlogBrowseView: View {
    @ObservedObject var viewModel: ReaderModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var sort: TechBlogSort
    @State private var selection: Set<Int> = []
    @State private var showingSettings = false
    @State private var loadedSettings: TechBlogSettings?

    init(viewModel: ReaderModel) {
        self.viewModel = viewModel
        _sort = State(initialValue: viewModel.techBlogSettings.feed == .new ? .newest : .points)
    }

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
        .frame(width: 720, height: 640)
        .task { await reload() }
        .onChange(of: showingSettings) { _, showing in reloadIfFiltersChanged(showing) }
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
        #endif
    }

    private var content: some View {
        let stories = TechBlogDiscovery.browse(viewModel.techBlogStories, query: query, sort: sort)
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
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
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .disabled(viewModel.isLoading)
            }
            Divider()
            footer.padding(16)
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
            ContentUnavailableView("No matching stories", systemImage: "newspaper",
                                   description: Text("Try a longer time window or lower minimums in import settings."))
        } else {
            ContentUnavailableView.search(text: query)
        }
    }

    private func row(_ story: TechBlogStory) -> some View {
        let saved = viewModel.isInLibrary(story)
        let selected = !saved && selection.contains(story.id)
        return Button {
            if selected { selection.remove(story.id) } else { selection.insert(story.id) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: saved ? "checkmark.circle" : selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(story.title)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(story.details)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if saved {
                    Text("Saved").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(saved)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
            HStack(spacing: 12) {
                Text("\(selectedStories.count) selected").font(.headline)
                Spacer(minLength: 0)
                Button("Clear") { selection.removeAll() }
                    .disabled(selection.isEmpty)
                importButton
            }
        }
    }

    private var importButton: some View {
        Button {
            Task {
                await viewModel.importTechBlogStories(selectedStories)
                selection.removeAll()
            }
        } label: {
            Label("Import ^[\(selectedStories.count) article](inflect: true)", systemImage: "square.and.arrow.down")
        }
        #if os(macOS)
        .buttonStyle(DesktopButtonStyle(primary: true))
        #else
        .buttonStyle(.borderedProminent)
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
        loadedSettings = viewModel.techBlogSettings
        await viewModel.loadTechBlogStories()
        selection = viewModel.suggestedTechBlogStoryIDs
    }
}

private extension TechBlogStory {
    var details: String {
        let points = "\(score.formatted()) \(score == 1 ? "point" : "points")"
        let replies = "\(comments.formatted()) \(comments == 1 ? "comment" : "comments")"
        let age = submittedAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
        return [site, points, replies, age].joined(separator: " · ")
    }
}
