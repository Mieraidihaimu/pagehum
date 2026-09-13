// Modified for Pagehum: unified application and command-line naming.
import SwiftUI

struct URLImportStatusView: View {
    @ObservedObject var viewModel: ReaderModel

    var body: some View {
        if let progress = viewModel.importProgress {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(progress)
            }
            .font(.callout)
        } else if let result = viewModel.importResult {
            VStack(alignment: .leading, spacing: 8) {
                Text(result.summary).font(.callout)
                if !result.failures.isEmpty {
                    DisclosureGroup("Failed links") {
                        ForEach(result.failures) { failure in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(failure.url.absoluteString).textSelection(.enabled)
                                Text(failure.message).foregroundStyle(.secondary)
                            }
                            .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                    }
                    Button("Retry failed links") {
                        let links = result.failures.map { $0.url.absoluteString }.joined(separator: "\n")
                        Task { await viewModel.importURLs(from: links) }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
    }
}
