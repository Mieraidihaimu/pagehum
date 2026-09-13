// Modified for Pagehum: unified application and command-line naming.
#if os(macOS)
import SwiftUI
import SwiftData

struct DesktopRootView: View {
    enum Page: String, CaseIterable {
        case home = "Add content", library = "Library", reader = "Now playing", settings = "Settings"
        var symbol: String {
            switch self {
            case .home: "plus"
            case .library: "books.vertical"
            case .reader: "headphones"
            case .settings: "slider.horizontal.3"
            }
        }
    }

    @ObservedObject var viewModel: ReaderModel
    @Binding var navigateToReader: Bool
    @ObservedObject private var queue: ListeningQueue
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlaylistItem.lastPlayed, order: .reverse) private var items: [PlaylistItem]
    @State private var page: Page = .home
    @State private var showStats = false
    @State private var showTechBlogSettings = false

    init(viewModel: ReaderModel, navigateToReader: Binding<Bool>) {
        self.viewModel = viewModel
        _navigateToReader = navigateToReader
        queue = viewModel.listeningQueue
    }

    private var continueItem: PlaylistItem? {
        items.first { $0.status == PlaylistItem.Status.inProgress.rawValue && $0.progressPercent < 1 }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(DesktopStyle.border).frame(width: 1)
            VStack(spacing: 0) {
                header
                ZStack {
                    // Keep form drafts alive while the user visits another screen.
                    DesktopInputView(viewModel: viewModel, continueItem: continueItem,
                                     openReader: { page = .reader }, openLibrary: { page = .library },
                                     openTechBlogSettings: openTechBlogSettings, openItem: open)
                        .opacity(page == .home ? 1 : 0)
                        .allowsHitTesting(page == .home)
                        .disabled(page != .home)
                        .accessibilityHidden(page != .home)
                    if page != .home { selectedPage }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let failure = queue.failure {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(queue.current?.title ?? "Listening paused").font(.headline)
                            Text(failure).font(.callout).foregroundStyle(DesktopStyle.secondary)
                        }
                        Spacer(minLength: 0)
                        Button("Retry") { queue.retry() }.disabled(!viewModel.isModelLoaded || viewModel.isLoading)
                        Button("Skip article") { queue.skip() }
                    }
                    .buttonStyle(DesktopButtonStyle())
                    .padding(16).background(DesktopStyle.panel)
                }
                if viewModel.content != nil || queue.isActive {
                    DesktopPlayerView(viewModel: viewModel, queue: queue, openReader: { page = .reader })
                }
            }
        }
        .frame(minWidth: 800, minHeight: 620)
        .background(DesktopStyle.canvas)
        .foregroundStyle(DesktopStyle.text)
        .tint(DesktopStyle.accent)
        .preferredColorScheme(.dark)
        .onChange(of: navigateToReader) { _, requested in
            if requested { page = .reader; navigateToReader = false }
        }
        .sheet(isPresented: $showStats) {
            VStack(spacing: 0) {
                HStack { Text("Listening stats").font(.headline); Spacer(); Button("Done") { showStats = false } }
                    .padding(20)
                StatsView()
            }
            .frame(width: 640, height: 560)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .foregroundStyle(DesktopStyle.accent)
                    .frame(width: 32, height: 32)
                    .background(DesktopStyle.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                Text("Pagehum").font(.system(size: 19, weight: .medium))
            }
            .padding(.horizontal, 8)
            VStack(spacing: 6) {
                ForEach([Page.home, .library, .reader], id: \.self) { navigationButton($0) }
            }
            Spacer()
            navigationButton(.settings)
        }
        .padding(.horizontal, 12)
        .padding(.top, 32)
        .padding(.bottom, 20)
        .frame(width: 192)
        .background(DesktopStyle.sidebar)
    }

    private func navigationButton(_ destination: Page) -> some View {
        Button { page = destination; showTechBlogSettings = false } label: {
            HStack(spacing: 10) {
                Image(systemName: destination.symbol).frame(width: 20)
                Text(destination.rawValue)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).frame(height: 38)
            .foregroundStyle(page == destination ? DesktopStyle.text : DesktopStyle.secondary)
            .background(page == destination ? DesktopStyle.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .leading) {
                if page == destination { Capsule().fill(DesktopStyle.accent).frame(width: 3, height: 18) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(page == destination ? .isSelected : [])
    }

    private var header: some View {
        HStack {
            if page == .settings && showTechBlogSettings {
                Button { showTechBlogSettings = false } label: {
                    Label("Settings", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Text("/ Tech blog imports").font(.system(size: 13)).foregroundStyle(DesktopStyle.secondary)
            } else {
                Text(page.rawValue).font(.system(size: 13)).foregroundStyle(DesktopStyle.secondary)
            }
            Spacer()
            Button { page = .home } label: { Image(systemName: "plus").frame(width: 24, height: 24) }
                .buttonStyle(.borderless)
                .help("Add content (⌘N)")
                .accessibilityLabel("Add content")
                .keyboardShortcut("n", modifiers: .command)
        }
        .padding(.horizontal, 28).frame(height: 52)
        .overlay(alignment: .bottom) { Rectangle().fill(DesktopStyle.border).frame(height: 1) }
    }

    @ViewBuilder private var selectedPage: some View {
        switch page {
        case .home: EmptyView()
        case .library:
            DesktopLibraryView(viewModel: viewModel, queue: queue, items: items, openItem: open, addContent: { page = .home })
        case .reader:
            if let content = viewModel.content {
                if let url = content.source.webURL {
                    WebReaderView(viewModel: viewModel, url: url, showsPlaybackControls: false)
                } else {
                    ReaderView(viewModel: viewModel, showsPlaybackControls: false, desktopLayout: true)
                }
            } else {
                ContentUnavailableView {
                    Label("Your next listen starts here", systemImage: "headphones")
                } description: { Text("Open an article, a PDF, or a piece of text.") }
                actions: { Button("Add content") { page = .home }.buttonStyle(DesktopButtonStyle(primary: true)) }
            }
        case .settings:
            if showTechBlogSettings {
                TechBlogImportSettingsView(viewModel: viewModel)
            } else {
                DesktopSettingsView(viewModel: viewModel, openStats: { showStats = true },
                                    openTechBlogSettings: openTechBlogSettings)
            }
        }
    }

    private func openTechBlogSettings() {
        showTechBlogSettings = true
        page = .settings
    }

    private func open(_ item: PlaylistItem) {
        // Merely viewing the current article should keep its queue intact.
        viewModel.openLibraryItem(item, preservingQueue: viewModel.currentPlaylistItemID == item.persistentModelID)
        page = .reader
    }
}
#endif
