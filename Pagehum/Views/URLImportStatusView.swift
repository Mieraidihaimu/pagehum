// Modified for Pagehum: unified application and command-line naming.
import SwiftUI

func importLinksTitle(_ count: Int) -> LocalizedStringKey {
    switch count {
    case 0: "Import links"
    case 1: "Import & open"
    default: "Import ^[\(count) link](inflect: true)"
    }
}

struct URLInputHint: View {
    let text: String

    var body: some View {
        let count = URLImportParser.urls(in: text).count
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: count > 0 ? "checkmark.circle" : "link")
                .accessibilityHidden(true)
            Group {
                if !hasText {
                    Text("Add one link to start reading, or several to build your library.")
                } else if count == 0 {
                    Text("No web links found. Try a link like example.com/article.")
                } else if count == 1 {
                    Text("1 article ready. Opens for reading after import.")
                } else {
                    Text("^[\(count) unique link](inflect: true) ready to save to your library.")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(count == 0 && hasText ? Color.orange : Color.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct URLImportStatusView: View {
    @ObservedObject var viewModel: ReaderModel

    var body: some View {
        if let progress = viewModel.importProgress {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(progress)
            }
            .font(.callout)
            .accessibilityElement(children: .combine)
        } else if let result = viewModel.importResult {
            VStack(alignment: .leading, spacing: 8) {
                Label(result.summary, systemImage: result.failures.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(result.failures.isEmpty ? Color.secondary : Color.orange)
                if !result.failures.isEmpty {
                    DisclosureGroup("Failed links") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(result.failures) { failure in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(failure.url.absoluteString).textSelection(.enabled)
                                        Text(failure.message).foregroundStyle(.secondary)
                                    }
                                    .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        .frame(height: min(160, CGFloat(result.failures.count) * 72))
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
