import SwiftUI

struct SettingsProgressView: View {
    @ObservedObject var viewModel: ReaderModel
    @ObservedObject private var offlineAudio: OfflineAudioManager
    var openReader: (() -> Void)?

    init(viewModel: ReaderModel, openReader: (() -> Void)?) {
        self.viewModel = viewModel
        self.openReader = openReader
        offlineAudio = viewModel.offlineAudio
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Article imports", systemImage: "square.and.arrow.down")
                    .font(.headline)
                if viewModel.importProgress != nil || viewModel.batchImportProgress != nil || viewModel.importResult != nil {
                    URLImportStatusView(viewModel: viewModel, scope: .all, openReader: openReader,
                                        showsDismissButton: true)
                } else {
                    Text("No article imports in progress")
                        .font(.callout)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label("Offline Audio", systemImage: "arrow.down.circle")
                    .font(.headline)
                offlineSaves
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var offlineSaves: some View {
        let saves = offlineAudio.progress.filter { $0.value.state != .ready }.sorted { lhs, rhs in
            let lhsSaving = lhs.value.state == .saving
            let rhsSaving = rhs.value.state == .saving
            if lhsSaving != rhsSaving { return lhsSaving }
            let order = lhs.value.title.localizedStandardCompare(rhs.value.title)
            return order == .orderedSame ? lhs.key < rhs.key : order == .orderedAscending
        }
        if saves.isEmpty {
            Text("No offline audio saves in progress")
                .font(.callout)
                .foregroundStyle(AppTheme.textSecondary)
        } else {
            let visibleCount = 3
            ForEach(saves.prefix(visibleCount), id: \.key) { save in
                offlineSaveRow(id: save.key, title: save.value.title)
            }
            if saves.count > visibleCount {
                DisclosureGroup("\(saves.count - visibleCount) more") {
                    ForEach(saves.dropFirst(visibleCount), id: \.key) { save in
                        offlineSaveRow(id: save.key, title: save.value.title)
                            .padding(.top, 6)
                    }
                }
                .font(.callout)
            }
        }
    }

    private func offlineSaveRow(id: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.callout).lineLimit(2)
            OfflineAudioProgressView(manager: offlineAudio, id: id)
        }
        .accessibilityElement(children: .combine)
    }
}
