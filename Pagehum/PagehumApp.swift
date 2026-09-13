// Modified for Pagehum: unified application and command-line naming.
import SwiftUI
import SwiftData
import MLX

@main
struct PagehumApp: App {
    let model = ReaderModel()
    let modelContainer: ModelContainer?
    let startupWarning: String?
    @State private var navigateToReader = false

    init() {
        GPU.set(cacheLimit: 512 * 1024 * 1024)
        GPU.set(memoryLimit: 2048 * 1024 * 1024)

        let schema = Schema([PlaylistItem.self, ListeningRecord.self])
        do {
            let container = try ModelContainer(for: schema)
            modelContainer = container
            startupWarning = nil
            model.modelContext = container.mainContext
            model.migrateLegacyPlaybackTextOffsets()
        } catch {
            do {
                let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
                let container = try ModelContainer(for: schema, configurations: configuration)
                modelContainer = container
                startupWarning = "The saved library could not be opened. Changes in this session will not be saved."
                model.modelContext = container.mainContext
            } catch {
                modelContainer = nil
                startupWarning = "The library could not be initialized: \(error.localizedDescription)"
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
                Group {
                    #if os(macOS)
                    DesktopRootView(viewModel: model, navigateToReader: $navigateToReader)
                    #else
                    NavigationStack {
                    HomeView(viewModel: model)
                        .navigationDestination(isPresented: $navigateToReader) {
                            if let url = model.content?.source.webURL {
                                WebReaderView(viewModel: model, url: url)
                            } else {
                                ReaderView(viewModel: model)
                            }
                        }
                    }
                    #endif
                }
                .safeAreaInset(edge: .top) {
                    if let startupWarning {
                        Text(startupWarning)
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .background(.orange.opacity(0.18))
                    }
                }
                .onOpenURL { url in
                    model.handleOpenURL(url)
                    Task {
                        await model.loadPendingSharedURL()
                        navigateToReader = model.content != nil
                    }
                }
                .onAppear {
                    model.checkForSharedURL()
                    if model.pendingSharedURL != nil {
                        Task {
                            await model.loadPendingSharedURL()
                            navigateToReader = model.content != nil
                        }
                    }
                }
                .modelContainer(modelContainer)
            } else {
                ContentUnavailableView(
                    "Library Unavailable",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(startupWarning ?? "The library could not be initialized.")
                )
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
}
