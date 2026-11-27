#if os(iOS)
import SwiftUI

/// Keeps web articles on their original page, including the publisher's images and layout.
struct PhoneReaderView: View {
    @ObservedObject var viewModel: ReaderModel

    var body: some View {
        Group {
            if let url = viewModel.content?.source.webURL {
                WebReaderView(viewModel: viewModel, url: url, showsPlaybackControls: false)
            } else {
                ReaderView(viewModel: viewModel, showsPlaybackControls: false, showsArticleHeading: true)
            }
        }
        .background(AppTheme.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PhonePlaybackControls(viewModel: viewModel)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(AppTheme.playerSurface)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AppTheme.playerBorder)
                        .frame(height: 1)
                }
        }
        .navigationTitle(viewModel.content?.title ?? "Reader")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.canvas, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                PhoneReaderMoreMenu(viewModel: viewModel)
            }
        }
    }
}

private struct PhoneReaderMoreMenu: View {
    @ObservedObject var viewModel: ReaderModel
    @ObservedObject private var queue: ListeningQueue
    @ObservedObject private var offlineAudio: OfflineAudioManager
    @State private var showsQueue = false

    init(viewModel: ReaderModel) {
        self.viewModel = viewModel
        queue = viewModel.listeningQueue
        offlineAudio = viewModel.offlineAudio
    }

    var body: some View {
        Menu {
            Text(viewModel.phonePlaybackStatus)
            if let id = viewModel.currentOfflineAudioID {
                OfflineAudioMenuActions(manager: offlineAudio, id: id, canSave: viewModel.isModelLoaded,
                                        canRemove: !viewModel.isPlaying && !viewModel.isPreparing,
                                        save: viewModel.saveCurrentAudioOffline)
            }
            if viewModel.playbackFailureCount > 0 {
                Text("\(viewModel.playbackFailureCount) sentences skipped")
            }
            Divider()
            Menu {
                Picker("Appearance", selection: $viewModel.currentArticleAppearance) {
                    ForEach(ReaderAppearance.allCases, id: \.self) { appearance in
                        Label(appearance.label, systemImage: appearance.systemImage)
                            .tag(appearance)
                    }
                }
            } label: {
                Label("Appearance", systemImage: viewModel.currentArticleAppearance.systemImage)
            }
            if let url = viewModel.content?.source.webURL {
                Link(destination: url) {
                    Label("Open in browser", systemImage: "arrow.up.right.square")
                }
            } else {
                Button("Larger text", systemImage: "textformat.size.larger") {
                    viewModel.textSize = min(32, viewModel.textSize + 2)
                }
                .disabled(viewModel.textSize >= 32)
                Button("Smaller text", systemImage: "textformat.size.smaller") {
                    viewModel.textSize = max(12, viewModel.textSize - 2)
                }
                .disabled(viewModel.textSize <= 12)
            }
            Toggle("Auto-scroll", systemImage: "arrow.up.and.down", isOn: $viewModel.autoScroll)
            Divider()
            Button("Restart from beginning", systemImage: "arrow.counterclockwise") {
                viewModel.restartFromBeginning()
            }
            .disabled(!viewModel.canPlayCurrentContent || viewModel.isLoading)
            if queue.isActive {
                Button("Next article", systemImage: "forward.end.fill") {
                    queue.skip()
                }
                .disabled(queue.upcoming.isEmpty || viewModel.isLoading)
            }
            Button("Up next, \(queue.upcoming.count) articles", systemImage: "list.bullet") {
                showsQueue = true
            }
        } label: {
            Image(systemName: queue.failure != nil || viewModel.playbackFailureCount > 0
                  ? "exclamationmark.circle" : "ellipsis")
                .font(.system(size: 20))
                .foregroundStyle(queue.failure != nil || viewModel.playbackFailureCount > 0
                                 ? AppTheme.destructiveText : AppTheme.accentPrimary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .tint(AppTheme.accentPrimary)
        .accessibilityLabel("Playback actions")
        .accessibilityValue(queue.failure ?? viewModel.phonePlaybackStatus)
        .sheet(isPresented: $showsQueue) {
            ListeningQueueSheet(viewModel: viewModel, queue: queue)
                .presentationDragIndicator(.visible)
        }
    }
}
#endif
