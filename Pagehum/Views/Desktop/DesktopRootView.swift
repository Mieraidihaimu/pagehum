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
    @State private var sidebarCollapsed = false
    @State private var showHeaderQueue = false
    @State private var showStats = false
    @State private var showTechBlogSettings = false
    @State private var showOfflineAudio = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: ReaderModel, navigateToReader: Binding<Bool>) {
        self.viewModel = viewModel
        _navigateToReader = navigateToReader
        queue = viewModel.listeningQueue
    }

    private var continueItem: PlaylistItem? {
        items.first { $0.status == PlaylistItem.Status.inProgress.rawValue && $0.progressPercent < 1 }
    }

    private var inProgressCount: Int {
        items.filter { $0.status == PlaylistItem.Status.inProgress.rawValue && $0.progressPercent < 1 }.count
    }

    var body: some View {
        HStack(spacing: 0) {
            if !sidebarCollapsed {
                sidebar
                    .transition(.move(edge: .leading))
                Rectangle().fill(DesktopStyle.border).frame(width: 1)
            }
            VStack(spacing: 0) {
                header
                if page != .settings || showTechBlogSettings || showOfflineAudio {
                    URLBatchImportBanner(viewModel: viewModel, openReader: { page = .reader })
                }
                ZStack {
                    // Keep form drafts alive while the user visits another screen.
                    DesktopInputView(viewModel: viewModel, continueItem: continueItem,
                                     openReader: { page = .reader }, openLibrary: { page = .library },
                                     openItem: open)
                        .opacity(page == .home ? 1 : 0)
                        .allowsHitTesting(page == .home)
                        .disabled(page != .home)
                        .accessibilityHidden(page != .home)
                    if page != .home { selectedPage }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let failure = queue.failure {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(AppTheme.destructiveText)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(queue.current?.title ?? "Listening paused")
                                .font(.headline)
                                .foregroundStyle(AppTheme.destructiveText)
                            Text(failure)
                                .font(.callout)
                                .foregroundStyle(AppTheme.destructiveText)
                        }
                        Spacer(minLength: 0)
                        Button("Retry") { queue.retry() }.disabled(!viewModel.isModelLoaded || viewModel.isLoading)
                        Button("Skip article") { queue.skip() }
                    }
                    .buttonStyle(DesktopButtonStyle())
                    .padding(16)
                    .background(AppTheme.destructiveSubtle)
                }
                if viewModel.content != nil || queue.isActive {
                    DesktopPlayerView(viewModel: viewModel, queue: queue, openReader: { page = .reader })
                }
            }
        }
        .frame(minWidth: 860, minHeight: 640)
        .background(DesktopStyle.canvas)
        .foregroundStyle(DesktopStyle.text)
        .tint(DesktopStyle.accent)
        .background {
            if page == .home {
                // Keep ⌘N active when the header's + button is hidden on the home screen.
                Button(action: openHome) { EmptyView() }
                    .keyboardShortcut("n", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: navigateToReader) { _, requested in
            if requested { page = .reader; navigateToReader = false }
        }
        .sheet(isPresented: $showStats) {
            VStack(spacing: 0) {
                HStack {
                    Text("Listening stats").font(.headline)
                    Spacer()
                    Button("Done") { showStats = false }
                        .keyboardShortcut(.cancelAction)
                }
                .padding(20)
                Divider()
                StatsView()
            }
            .frame(minWidth: 620, idealWidth: 720, minHeight: 540, idealHeight: 620)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                // Clear macOS window traffic lights (x: 0..78) in hiddenTitleBar windows.
                Spacer(minLength: 78)
                sidebarToggleButton
            }
            .padding(.top, 14)

            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .foregroundStyle(DesktopStyle.accent)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.accentPrimarySubtle, in: RoundedRectangle(cornerRadius: 10))
                Text("Pagehum").font(.system(size: 19, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.top, 16)
            .padding(.bottom, 24)

            VStack(spacing: 6) {
                ForEach([Page.home, .library, .reader], id: \.self) { navigationButton($0) }
            }
            Spacer()
            navigationButton(.settings)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 20)
        .frame(width: 212)
        .background(DesktopStyle.sidebar)
    }

    private var sidebarToggleButton: some View {
        Button(action: toggleSidebar) {
            Image(systemName: "sidebar.left")
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(DesktopStyle.secondary)
        .help(sidebarCollapsed ? "Show sidebar (⌘⌥S)" : "Hide sidebar (⌘⌥S)")
        .accessibilityLabel(sidebarCollapsed ? "Show sidebar" : "Hide sidebar")
        .keyboardShortcut("s", modifiers: [.command, .option])
    }

    private func toggleSidebar() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            sidebarCollapsed.toggle()
        }
    }

    private func openHome() {
        page = .home
        showTechBlogSettings = false
        showOfflineAudio = false
    }

    private func navigationButton(_ destination: Page) -> some View {
        let isSelected = page == destination
        return Button { page = destination; showTechBlogSettings = false; showOfflineAudio = false } label: {
            HStack(spacing: 10) {
                Image(systemName: destination.symbol).frame(width: 20)
                Text(destination.rawValue)
                Spacer(minLength: 0)
                if destination == .library, inProgressCount > 0 {
                    Text("\(inProgressCount)")
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(isSelected ? AppTheme.accentText : AppTheme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? AppTheme.accentPrimarySubtle : AppTheme.elevated, in: Capsule())
                } else if destination == .reader, viewModel.content != nil {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundStyle(viewModel.isPlaying || viewModel.isPreparing ? AppTheme.ctaPrimary : AppTheme.textMuted)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12).frame(height: 38)
            .foregroundStyle(isSelected ? DesktopStyle.accent : DesktopStyle.secondary)
            .background(isSelected ? AppTheme.accentPrimarySubtle : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .leading) {
                if isSelected { Capsule().fill(DesktopStyle.accent).frame(width: 3, height: 18) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var header: some View {
        HStack(spacing: 12) {
            if sidebarCollapsed {
                sidebarToggleButton
            }
            if page == .settings && (showTechBlogSettings || showOfflineAudio) {
                HStack(spacing: 6) {
                    Button { showTechBlogSettings = false; showOfflineAudio = false } label: {
                        Label("Settings", systemImage: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(DesktopStyle.secondary)
                    Text(showOfflineAudio ? "/ Offline Audio" : "/ Tech blogs")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DesktopStyle.secondary)
                }
            } else {
                Text(page.rawValue)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesktopStyle.text)
            }
            Spacer(minLength: 12)
            headerTrailingActions
        }
        .padding(.leading, sidebarCollapsed ? 84 : 28)
        .padding(.trailing, 28)
        .frame(height: 52)
        .overlay(alignment: .bottom) { Rectangle().fill(DesktopStyle.border).frame(height: 1) }
    }

    @ViewBuilder
    private var headerTrailingActions: some View {
        HStack(spacing: 10) {
            if page == .reader, let content = viewModel.content {
                if content.source.webURL == nil {
                    textSizePill
                }
                if let webURL = content.source.webURL {
                    Link(destination: webURL) {
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(DesktopStyle.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .help("Open in browser")
                    .accessibilityLabel("Open in browser")
                }
                if let offlineID = viewModel.currentOfflineAudioID {
                    OfflineAudioButton(
                        manager: viewModel.offlineAudio,
                        id: offlineID,
                        canSave: viewModel.isModelLoaded,
                        canRemove: !viewModel.isPlaying && !viewModel.isPreparing,
                        compact: true,
                        save: viewModel.saveCurrentAudioOffline
                    )
                    .buttonStyle(.borderless)
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .foregroundStyle(DesktopStyle.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                }
                Button { showHeaderQueue.toggle() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                        if !queue.upcoming.isEmpty {
                            Text("\(queue.upcoming.count)")
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(AppTheme.accentPrimarySubtle, in: Capsule())
                                .foregroundStyle(AppTheme.accentText)
                        }
                    }
                    .frame(minWidth: 28, minHeight: 28)
                    .padding(.horizontal, queue.upcoming.isEmpty ? 0 : 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(showHeaderQueue ? DesktopStyle.accent : DesktopStyle.secondary)
                .help("Listening queue")
                .accessibilityLabel(queue.upcoming.isEmpty ? "Listening queue" : "Listening queue, \(queue.upcoming.count) upcoming")
                .popover(isPresented: $showHeaderQueue, arrowEdge: .bottom) {
                    DesktopQueueView(viewModel: viewModel, queue: queue)
                }

                Rectangle()
                    .fill(DesktopStyle.border)
                    .frame(width: 1, height: 16)
            }

            if page != .home {
                Button(action: openHome) {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(DesktopStyle.secondary)
                .help("Add content (⌘N)")
                .accessibilityLabel("Add content")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    private var textSizePill: some View {
        HStack(spacing: 0) {
            Button {
                viewModel.textSize = max(12, viewModel.textSize - 2)
            } label: {
                Text("A-")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.textSize <= 12)
            .foregroundStyle(viewModel.textSize <= 12 ? AppTheme.textMuted : DesktopStyle.text)
            .help("Smaller text")
            .accessibilityLabel("Smaller text")

            Rectangle()
                .fill(AppTheme.borderSubtle)
                .frame(width: 1)

            Button {
                viewModel.textSize = min(32, viewModel.textSize + 2)
            } label: {
                Text("A+")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.textSize >= 32)
            .foregroundStyle(viewModel.textSize >= 32 ? AppTheme.textMuted : DesktopStyle.text)
            .help("Larger text")
            .accessibilityLabel("Larger text")
        }
        .frame(height: 28)
        .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle, lineWidth: 1)
        )
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
            if showOfflineAudio {
                OfflineAudioListView(viewModel: viewModel, openPlayer: { page = .reader })
            } else if showTechBlogSettings {
                TechBlogImportSettingsView(viewModel: viewModel)
            } else {
                DesktopSettingsView(viewModel: viewModel, openStats: { showStats = true },
                                    openTechBlogSettings: openTechBlogSettings,
                                    openOfflineAudio: { showOfflineAudio = true },
                                    openReader: { page = .reader })
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
