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
        .background(Color.platformGroupedBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PhonePlaybackControls(viewModel: viewModel)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
        }
        .navigationTitle(viewModel.content?.title ?? "Reader")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let id = viewModel.currentOfflineAudioID {
                    OfflineAudioButton(manager: viewModel.offlineAudio, id: id, canSave: viewModel.isModelLoaded,
                                       canRemove: !viewModel.isPlaying && !viewModel.isPreparing,
                                       save: viewModel.saveCurrentAudioOffline)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if let url = viewModel.content?.source.webURL {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Open in browser")
                } else {
                    Menu {
                        Button("Larger text", systemImage: "textformat.size.larger") {
                            viewModel.textSize = min(32, viewModel.textSize + 2)
                        }
                        .disabled(viewModel.textSize >= 32)
                        Button("Smaller text", systemImage: "textformat.size.smaller") {
                            viewModel.textSize = max(12, viewModel.textSize - 2)
                        }
                        .disabled(viewModel.textSize <= 12)
                    } label: {
                        Image(systemName: "textformat.size").frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Reading options")
                }
            }
        }
    }
}
#endif
