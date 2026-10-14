import SwiftUI

/// Offers the one-time Kokoro download while system voices stand in; renders nothing otherwise.
struct VoiceModelDownloadView: View {
    @ObservedObject var viewModel: ReaderModel

    var body: some View {
        if viewModel.canDownloadVoiceModel {
            VStack(alignment: .leading, spacing: 8) {
                switch viewModel.modelDownload {
                case .downloading(let fraction):
                    ProgressView(value: fraction) {
                        Text("Downloading natural voices…")
                    } currentValueLabel: {
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                    }
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                    downloadButton(title: "Try again")
                case .idle:
                    Text("Using system voices. Download natural voices for clearer, more human speech.")
                        .foregroundStyle(.secondary)
                    downloadButton(title: "Download natural voices (\(sizeLabel))")
                }
            }
            .font(.callout)
        }
    }

    private var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: viewModel.voiceModelDownloadSize, countStyle: .file)
    }

    private func downloadButton(title: LocalizedStringKey) -> some View {
        Button {
            Task { await viewModel.downloadVoiceModel() }
        } label: {
            Label(title, systemImage: "arrow.down.circle")
        }
    }
}
