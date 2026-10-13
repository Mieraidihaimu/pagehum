// Modified for Pagehum: unified application and command-line naming.
#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

struct DesktopInputView: View {
    @ObservedObject var viewModel: ReaderModel
    var continueItem: PlaylistItem?
    var openReader: () -> Void
    var openLibrary: () -> Void
    var openItem: (PlaylistItem) -> Void
    @State private var input = HomeView.InputTab.url
    @State private var url = ""
    @State private var text = ""
    @State private var showFilePicker = false
    @FocusState private var urlFocused: Bool

    var body: some View {
        DesktopPage {
            DesktopHeading(title: "Make time for a good read.", subtitle: "Add an article, then listen at your own pace.")
            VStack(alignment: .leading, spacing: 20) {
                Picker("Input type", selection: $input) {
                    ForEach(HomeView.InputTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 240)
                .disabled(viewModel.isLoading)
                inputForm
                    .disabled(viewModel.isLoading)
                if viewModel.isLoading && viewModel.importProgress == nil {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Opening article…")
                    }.font(.callout).foregroundStyle(DesktopStyle.secondary)
                }
            }
            .padding(24)
            .background(DesktopStyle.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DesktopStyle.border))

            TechBlogQuickImportView(viewModel: viewModel)
                .padding(.top, 20)

            VStack(alignment: .leading, spacing: 12) {
                URLImportStatusView(viewModel: viewModel)
                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.callout).foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 16)

            HStack {
                Text("Continue listening").font(.system(size: 16, weight: .medium))
                Spacer()
                Button(action: openLibrary) { Label("View library", systemImage: "arrow.right").labelStyle(.titleAndIcon) }
                    .buttonStyle(.borderless)
            }
            .padding(.top, 32).padding(.bottom, 12)
            if let continueItem {
                DesktopArticleRow(item: continueItem, action: { openItem(continueItem) })
            } else {
                VStack(spacing: 8) {
                    Text("Your next good read starts here.").font(.headline)
                    Text("Articles you start will appear here, ready to resume.")
                        .foregroundStyle(DesktopStyle.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 32)
            }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let file):
                guard file.startAccessingSecurityScopedResource() else {
                    viewModel.errorMessage = "This PDF couldn’t be accessed. Choose it again."; return
                }
                Task {
                    defer { file.stopAccessingSecurityScopedResource() }
                    await viewModel.loadPDF(file)
                    finishOpening()
                }
            case .failure(let error): viewModel.errorMessage = error.localizedDescription
            }
        }
        .onChange(of: input) { _, _ in viewModel.errorMessage = nil }
    }

    @ViewBuilder private var inputForm: some View {
        switch input {
        case .url:
            VStack(alignment: .leading, spacing: 8) {
                Text("Article URLs").font(.callout).foregroundStyle(DesktopStyle.secondary)
                TextField("Paste article links", text: $url, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.plain).padding(12)
                    .background(DesktopStyle.sidebar, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DesktopStyle.secondary.opacity(0.55)))
                    .focused($urlFocused)
                    .accessibilityLabel("Article URLs")
                Text("Separate links with spaces, new lines, or commas.")
                    .font(.caption).foregroundStyle(DesktopStyle.secondary)
            }
            HStack(spacing: 8) {
                Button { importLinks(url, fromText: false) } label: {
                    Label(importLinksTitle(URLImportParser.urls(in: url).count), systemImage: "bookmark")
                }
                .buttonStyle(DesktopButtonStyle(primary: true))
                .disabled(URLImportParser.urls(in: url).isEmpty || viewModel.isLoading)
                if URLImportParser.urls(in: url).count == 1 {
                    Button(action: load) { Label("Open page", systemImage: "arrow.right") }
                        .buttonStyle(DesktopButtonStyle())
                        .disabled(viewModel.isLoading)
                }
            }
        case .file:
            VStack(alignment: .leading, spacing: 16) {
                Text("Open a PDF from your Mac.").foregroundStyle(DesktopStyle.secondary)
                Button { showFilePicker = true } label: { Label("Choose PDF…", systemImage: "doc") }
                    .buttonStyle(DesktopButtonStyle(primary: true))
                    .disabled(viewModel.isLoading)
            }
        case .text:
            VStack(alignment: .leading, spacing: 8) {
                Text("Paste text or article links").font(.callout).foregroundStyle(DesktopStyle.secondary)
                TextEditor(text: $text)
                    .font(.body).scrollContentBackground(.hidden)
                    .padding(8).frame(height: 144)
                    .background(DesktopStyle.sidebar, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DesktopStyle.secondary.opacity(0.55)))
                    .accessibilityLabel("Text to read aloud")
                if !URLImportParser.urls(in: text).isEmpty {
                    Button { importLinks(text, fromText: true) } label: {
                        Label("Import \(URLImportParser.urls(in: text).count) links", systemImage: "bookmark")
                    }
                    .buttonStyle(DesktopButtonStyle(primary: true))
                    .disabled(viewModel.isLoading)
                }
                Button(action: load) { Label("Read text", systemImage: "arrow.right") }
                    .buttonStyle(DesktopButtonStyle(primary: URLImportParser.urls(in: text).isEmpty))
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
                    .padding(.top, 8)
            }
        }
    }

    private func load() {
        Task {
            if input == .url, let link = URLImportParser.urls(in: url).first { await viewModel.loadURL(link.absoluteString) }
            else { await viewModel.loadText(text) }
            finishOpening()
        }
    }

    private func importLinks(_ value: String, fromText: Bool) {
        Task {
            if let result = await viewModel.importURLs(from: value), result.failures.isEmpty {
                if fromText { text = "" } else { url = "" }
            }
        }
    }

    private func finishOpening() {
        guard viewModel.errorMessage == nil, viewModel.content != nil else { return }
        openReader()
    }
}
#endif
