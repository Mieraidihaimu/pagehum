#if os(iOS)
import SwiftUI

struct PhoneRootView: View {
    private enum Tab: Hashable { case add, library, listen, settings }

    @ObservedObject var viewModel: ReaderModel
    @Binding var navigateToReader: Bool
    @State private var selectedTab: Tab = .add

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(viewModel: viewModel, usesTabNavigation: true)
            }
            .tabItem { Label("Add", systemImage: "plus.circle") }
            .tag(Tab.add)

            NavigationStack {
                PlaylistView(viewModel: viewModel, addContent: { selectedTab = .add })
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
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        Button("Open library") { selectedTab = .library }
                    }
                    .navigationTitle("Listen")
                }
            }
            .tabItem { Label("Listen", systemImage: viewModel.isPlaying ? "waveform" : "headphones") }
            .tag(Tab.listen)

            NavigationStack {
                SettingsView(viewModel: viewModel)
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(Tab.settings)
        }
        .onChange(of: navigateToReader) { _, requested in
            if requested {
                selectedTab = .listen
                navigateToReader = false
            }
        }
    }
}
#endif
