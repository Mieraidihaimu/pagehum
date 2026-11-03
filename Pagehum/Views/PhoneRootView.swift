#if os(iOS)
import SwiftUI

struct PhoneRootView: View {
    private enum Tab: Hashable { case add, library, listen, settings }

    @ObservedObject var viewModel: ReaderModel
    @Binding var navigateToLibrary: Bool
    @State private var selectedTab: Tab = .add
    @State private var isKeyboardPresented = false

    var body: some View {
        TabView(selection: $selectedTab) {
            browsingTab {
                HomeView(viewModel: viewModel, usesTabNavigation: true, openReader: openReader, openLibrary: openLibrary)
            }
            .tabItem { Label("Add", systemImage: "plus.circle") }
            .tag(Tab.add)

            browsingTab(showsMiniPlayer: false) {
                PlaylistView(viewModel: viewModel, addContent: { selectedTab = .add }, openReader: openReader)
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }
            .tag(Tab.library)

            NavigationStack {
                if viewModel.content != nil {
                    PhoneReaderView(viewModel: viewModel)
                } else {
                    ContentUnavailableView {
                        Label("Your next listen starts here", systemImage: "headphones")
                    } description: {
                        Text("Add an article or choose one from your library.")
                    } actions: {
                        Button("Add an article") { selectedTab = .add }
                            .buttonStyle(ThemeButtonStyle())
                            .controlSize(.large)
                        Button("Open library") { selectedTab = .library }
                    }
                    .navigationTitle("Listen")
                }
            }
            .tabItem { Label("Listen", systemImage: viewModel.isPlaying ? "waveform" : "headphones") }
            .tag(Tab.listen)

            browsingTab {
                SettingsView(viewModel: viewModel, openReader: openReader, openLibrary: openLibrary)
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(Tab.settings)
        }
        .toolbarBackground(AppTheme.surface, for: .tabBar)
        .toolbarBackground(AppTheme.canvas, for: .navigationBar)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardPresented = false
        }
        .onChange(of: navigateToLibrary) { _, requested in
            if requested {
                openLibrary()
                navigateToLibrary = false
            }
        }
    }

    private func browsingTab<Content: View>(showsMiniPlayer: Bool = true, @ViewBuilder content: () -> Content) -> some View {
        // Reserve space only in tabs that show the mini-player; Library gets
        // the full height for its articles and selection actions.
        VStack(spacing: 0) {
            NavigationStack { content() }
            if showsMiniPlayer && !isKeyboardPresented {
                PhoneMiniPlayer(viewModel: viewModel, openReader: openReader)
            }
        }
        .background(AppTheme.canvas)
    }

    private func openReader() {
        selectedTab = .listen
    }

    private func openLibrary() {
        selectedTab = .library
    }
}
#endif
