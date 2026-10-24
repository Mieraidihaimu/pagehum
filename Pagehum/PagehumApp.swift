// Modified for Pagehum: unified application and command-line naming.
import SwiftUI
import SwiftData

@main
struct PagehumApp: App {
    @StateObject private var model = ReaderModel()
    @StateObject private var library = LibraryStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigateToReader = false
    @State private var importingSharedURL = false
    @State private var sharedImportFailed = false

    var body: some Scene {
        WindowGroup {
            if let modelContainer = library.container {
                Group {
                    #if os(macOS)
                    DesktopRootView(viewModel: model, navigateToReader: $navigateToReader)
                    #else
                    PhoneRootView(viewModel: model, navigateToReader: $navigateToReader)
                    #endif
                }
                .safeAreaInset(edge: .top) {
                    if let message = model.librarySaveError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(message)
                            Button("Retry saving") { model.saveLibraryChanges() }
                        }
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.orange.opacity(0.18))
                    }
                }
                .onOpenURL { url in
                    model.handleOpenURL(url)
                    importSharedURL()
                }
                .alert("Couldn’t import shared link", isPresented: $sharedImportFailed) {
                    Button("Retry") { importSharedURL() }
                    Button("Discard link", role: .destructive) { model.discardPendingSharedURL() }
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(model.errorMessage ?? "Please try again.")
                }
                .onAppear {
                    model.modelContext = modelContainer.mainContext
                    model.migrateLegacyPlaybackTextOffsets()
                    importSharedURL()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        importSharedURL()
                    } else {
                        model.saveProgressNow()
                    }
                }
                .modelContainer(modelContainer)
            } else {
                ContentUnavailableView {
                    Label("Library Unavailable", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(library.errorMessage ?? "The library could not be initialized.")
                } actions: {
                    Button("Try again") { library.retry() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 780)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Playback") {
                Button("Play / Pause") {
                    model.togglePlayback()
                }
                .keyboardShortcut(.space, modifiers: [])

                Divider()

                Button("Skip Backward") {
                    model.skipBackward()
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)

                Button("Skip Forward") {
                    model.skipForward()
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

                Divider()

                Button("Faster") {
                    let speeds: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0, 2.25, 2.5, 3.0]
                    if let idx = speeds.firstIndex(of: model.speed), idx + 1 < speeds.count {
                        model.speed = speeds[idx + 1]
                    }
                }
                .keyboardShortcut("]", modifiers: .command)

                Button("Slower") {
                    let speeds: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0, 2.25, 2.5, 3.0]
                    if let idx = speeds.firstIndex(of: model.speed), idx > 0 {
                        model.speed = speeds[idx - 1]
                    }
                }
                .keyboardShortcut("[", modifiers: .command)
            }
        }
        #endif
    }

    private func importSharedURL() {
        guard !importingSharedURL, !model.isLoading, model.modelContext != nil else { return }
        if model.pendingSharedURL == nil { model.checkForSharedURL() }
        guard model.pendingSharedURL != nil else { return }
        importingSharedURL = true
        Task {
            await model.loadPendingSharedURL()
            navigateToReader = model.errorMessage == nil && model.content != nil
            sharedImportFailed = model.errorMessage != nil
            importingSharedURL = false
        }
    }
}
