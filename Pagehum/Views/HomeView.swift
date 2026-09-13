// Modified for Pagehum: unified application and command-line naming.
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {

    enum InputTab: String, CaseIterable {
        case url = "URL"
        case file = "File"
        case text = "Text"
    }

    @ObservedObject var viewModel: ReaderModel
    @State private var selectedTab: InputTab = .url
    @State private var urlString = ""
    @State private var pastedText = ""
    @State private var showFilePicker = false
    @State private var navigateToReader = false
    @FocusState private var isURLFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer(minLength: 40)

                // Hero
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.accentColor.opacity(0.15), .accentColor.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(Color.accentColor)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityHidden(true)

                    Text("Pagehum")
                        .font(.largeTitle.weight(.bold))
                        .accessibilityAddTraits(.isHeader)

                    if viewModel.isModelLoaded {
                        Text("Read anything aloud")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Loading model…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Input selector
                VStack(spacing: 20) {
                    Picker("Input", selection: $selectedTab) {
                        ForEach(InputTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(viewModel.isLoading)

                    Group {
                        switch selectedTab {
                        case .url: urlInputView
                        case .file: fileInputView
                        case .text: textInputView
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
                .padding(20)
                .background(.background, in: RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.06), radius: 10, y: 4)

                TechBlogQuickImportView(viewModel: viewModel) {
                    NavigationLink {
                        TechBlogImportSettingsView(viewModel: viewModel)
                    } label: {
                        Label("Import settings", systemImage: "slider.horizontal.3")
                    }
                }

                URLImportStatusView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
        }
        .background(Color.platformGroupedBackground)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    PlaylistView(viewModel: viewModel)
                } label: {
                    Image(systemName: "books.vertical")
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel("Library")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView(viewModel: viewModel)
                } label: {
                    Image(systemName: "gearshape")
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel("Settings")
            }
            #else
            ToolbarItem(placement: .navigation) {
                NavigationLink {
                    PlaylistView(viewModel: viewModel)
                } label: {
                    Image(systemName: "books.vertical")
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel("Library")
            }
            ToolbarItem(placement: .automatic) {
                NavigationLink {
                    SettingsView(viewModel: viewModel)
                } label: {
                    Image(systemName: "gearshape")
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel("Settings")
            }
            #endif
        }
        .navigationDestination(isPresented: $navigateToReader) {
            if let url = viewModel.content?.source.webURL {
                WebReaderView(viewModel: viewModel, url: url)
            } else {
                ReaderView(viewModel: viewModel)
            }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
            handleFileSelection(result)
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .overlay(alignment: .bottom) {
            if viewModel.savedConfirmation {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Saved to Reading Queue")
                        .fontWeight(.medium)
                }
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.green.gradient, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 24)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(reduceMotion ? nil : .default) { viewModel.savedConfirmation = false }
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.4), value: viewModel.savedConfirmation)
    }

    // MARK: - Inputs

    private var urlInputView: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                TextField("Paste article links", text: $urlString, axis: .vertical)
                    .lineLimit(3...6)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .focused($isURLFieldFocused)
                    .accessibilityLabel("Article URLs")
                if !urlString.isEmpty {
                    Button {
                        urlString = ""
                        isURLFieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Clear article URLs")
                }
            }
            .padding(14)
            .background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12))

            Text("Separate links with spaces, new lines, or commas.")
                .font(.caption).foregroundStyle(.secondary)
            actionButton("Import \(URLImportParser.urls(in: urlString).count) links", icon: "bookmark.fill") {
                importLinks(urlString, fromText: false)
            }
            .disabled(URLImportParser.urls(in: urlString).isEmpty)
            if URLImportParser.urls(in: urlString).count == 1 {
                Button("Open page") { loadURL() }
                    .disabled(viewModel.isLoading)
            }
        }
    }

    private var fileInputView: some View {
        VStack(spacing: 14) {
            Button {
                showFilePicker = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.fill")
                        .font(.title3)
                        .foregroundStyle(.red.opacity(0.8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Choose PDF")
                            .font(.subheadline.weight(.medium))
                        Text("Select a document from Files")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
            }
            .foregroundStyle(.primary)
        }
    }

    private var textInputView: some View {
        VStack(spacing: 14) {
            TextEditor(text: $pastedText)
                .accessibilityLabel("Text to read aloud")
                .frame(height: 120)
                .padding(10)
                .background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
                .scrollContentBackground(.hidden)
                .overlay(alignment: .topLeading) {
                    if pastedText.isEmpty {
                        Text("Paste text or article links here…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }

            if !URLImportParser.urls(in: pastedText).isEmpty {
                actionButton("Import \(URLImportParser.urls(in: pastedText).count) links", icon: "bookmark.fill") {
                    importLinks(pastedText, fromText: true)
                }
            }
            actionButton("Read Text", icon: "play.circle.fill") { loadText() }
                .disabled(pastedText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: icon)
                    Text(title)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
        }
        .disabled(viewModel.isLoading)
    }

    // MARK: - Actions

    private func loadURL() {
        Task {
            guard let url = URLImportParser.urls(in: urlString).first else { return }
            await viewModel.loadURL(url.absoluteString)
            if viewModel.errorMessage == nil, viewModel.content != nil {
                urlString = ""
                navigateToReader = true
            }
        }
    }

    private func importLinks(_ value: String, fromText: Bool) {
        Task {
            if let result = await viewModel.importURLs(from: value), result.failures.isEmpty {
                if fromText { pastedText = "" } else { urlString = "" }
            }
        }
    }

    private func loadText() {
        Task {
            await viewModel.loadText(pastedText)
            if viewModel.content != nil { navigateToReader = true }
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                viewModel.errorMessage = "Cannot access file"; return
            }
            Task {
                await viewModel.loadPDF(url)
                url.stopAccessingSecurityScopedResource()
                if viewModel.content != nil { navigateToReader = true }
            }
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }
}
