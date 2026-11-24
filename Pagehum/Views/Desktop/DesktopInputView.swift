// Modified for Pagehum: unified application and command-line naming.
#if os(macOS)
import SwiftUI
import SwiftData
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
    @FocusState private var textFocused: Bool

    var body: some View {
        DesktopPage {
            DesktopHeading(title: "Make time for a good read.", subtitle: "Add an article, then listen at your own pace.")
            VStack(alignment: .leading, spacing: 20) {
                ThemeSegmentedPicker(title: "Input type", options: HomeView.InputTab.allCases, selection: $input) {
                    Text($0.rawValue)
                }
                .frame(width: 240)
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
            .themeCard(cornerRadius: 12)

            TechBlogQuickImportView(viewModel: viewModel, openReader: openReader)
                .padding(.top, 20)

            VStack(alignment: .leading, spacing: 12) {
                URLImportStatusView(viewModel: viewModel)
                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.callout).foregroundStyle(AppTheme.destructiveText)
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
                Text("Article links").font(.callout.weight(.medium))
                HStack(alignment: .top, spacing: 8) {
                    TextField("Paste article links", text: $url, axis: .vertical)
                        .lineLimit(3...6)
                        .textFieldStyle(.plain)
                        .focused($urlFocused)
                        .accessibilityLabel("Article URLs")
                    if !url.isEmpty {
                        clearInputButton(helpText: "Clear links") { url = "" }
                    }
                }
                .padding(12)
                .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 8))
                .overlay(inputBorder(focused: urlFocused))
                URLInputHint(text: url)
            }
            HStack(spacing: 8) {
                Button { importLinks(url, fromText: false) } label: {
                    Label(importLinksTitle(URLImportParser.urls(in: url).count), systemImage: "bookmark")
                }
                .buttonStyle(DesktopButtonStyle(primary: true))
                .disabled(URLImportParser.urls(in: url).isEmpty || viewModel.isImportBusy)
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
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .focused($textFocused)
                        .padding(.trailing, text.isEmpty ? 0 : 24)
                        .accessibilityLabel("Text to read aloud")

                    if text.isEmpty {
                        Text("Paste or type text to listen…")
                            .font(.body)
                            .foregroundStyle(AppTheme.textMuted)
                            .padding(.horizontal, 5)
                            .allowsHitTesting(false)
                    }
                }
                .padding(10)
                .frame(height: 144)
                .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    if !text.isEmpty {
                        clearInputButton(helpText: "Clear text") { text = "" }
                            .padding(10)
                    }
                }
                .overlay(inputBorder(focused: textFocused))
                if !URLImportParser.urls(in: text).isEmpty {
                    Button { importLinks(text, fromText: true) } label: {
                        Label(importLinksTitle(URLImportParser.urls(in: text).count), systemImage: "bookmark")
                    }
                    .buttonStyle(DesktopButtonStyle(primary: true))
                    .disabled(viewModel.isImportBusy)
                }
                Button(action: load) { Label("Read pasted text", systemImage: "doc.text") }
                    .buttonStyle(DesktopButtonStyle(primary: URLImportParser.urls(in: text).isEmpty))
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
                    .padding(.top, 8)
            }
        }
    }

    private func inputBorder(focused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(focused ? AppTheme.borderFocus : DesktopStyle.border, lineWidth: focused ? 1.5 : 1)
    }

    private func clearInputButton(helpText: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(AppTheme.textMuted)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(helpText)
    }

    private func load() {
        Task {
            await viewModel.loadText(text)
            finishOpening()
        }
    }

    private func importLinks(_ value: String, fromText: Bool) {
        Task {
            if let result = await viewModel.importURLs(from: value), result.failures.isEmpty {
                if fromText {
                    if text == value { text = "" }
                } else if url == value {
                    url = ""
                }
                if let item = result.singleItem,
                   viewModel.openLibraryItem(item, preservingQueue: viewModel.currentPlaylistItemID == item.persistentModelID) {
                    openReader()
                }
            }
        }
    }

    private func finishOpening() {
        guard viewModel.errorMessage == nil, viewModel.content != nil else { return }
        openReader()
    }
}
#endif
