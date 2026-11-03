// Modified for Pagehum: unified application and command-line naming.
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct HomeView: View {

    enum InputTab: String, CaseIterable {
        case url = "URL"
        case file = "File"
        case text = "Text"
    }

    @ObservedObject var viewModel: ReaderModel
    var usesTabNavigation = false
    var openReader: (() -> Void)? = nil
    var openLibrary: (() -> Void)? = nil
    @State private var selectedTab: InputTab = .url
    @State private var urlString = ""
    @State private var pastedText = ""
    @State private var showFilePicker = false
    @State private var navigateToReader = false
    @FocusState private var isURLFieldFocused: Bool
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                #if os(macOS)
                // Minimized Brand Header
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.accentPrimarySubtle, AppTheme.accentPrimarySubtle],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        Image(systemName: "waveform")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(AppTheme.accentPrimary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pagehum")
                            .font(.system(size: 20, weight: .bold, design: .rounded))

                        if viewModel.isModelLoaded {
                            Text("Read anything aloud")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        } else {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.mini)
                                Text("Loading model…")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)
                #endif

                #if os(iOS)
                VStack(alignment: .leading, spacing: 6) {
                    Text("What would you like to listen to?")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Add a link, a PDF, or your own text.")
                        .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                #endif

                // Input selector
                VStack(spacing: 16) {
                    #if os(iOS)
                    if dynamicTypeSize.isAccessibilitySize {
                        inputPicker.pickerStyle(.menu)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    } else {
                        ThemeSegmentedPicker(title: "Input", options: InputTab.allCases, selection: $selectedTab) {
                            Text($0.phoneTitle)
                        }
                        .disabled(viewModel.isLoading)
                    }
                    #else
                    ThemeSegmentedPicker(title: "Input", options: InputTab.allCases, selection: $selectedTab) {
                        Text($0.rawValue)
                    }
                    .disabled(viewModel.isLoading)
                    #endif

                    Group {
                        switch selectedTab {
                        case .url: urlInputView
                        case .file: fileInputView
                        case .text: textInputView
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
                .padding(18)
                .themeCard(cornerRadius: 18)

                URLImportStatusView(viewModel: viewModel, openLibrary: openLibrary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                #if os(iOS)
                if let content = viewModel.content {
                    Button(action: showReader) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Continue reading", systemImage: "book")
                                .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accentPrimary)
                            HStack {
                                Text(content.title).font(.headline).lineLimit(2).foregroundStyle(AppTheme.textPrimary)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right").foregroundStyle(AppTheme.textSecondary)
                            }
                            ProgressView(value: min(1, max(0, viewModel.progress)))
                                .tint(AppTheme.accentPrimaryFill)
                                .accessibilityLabel("Reading progress")
                        }
                        .padding(16)
                        .themeCard(cornerRadius: 16)
                    }
                    .buttonStyle(.plain)
                }
                #endif

                TechBlogQuickImportView(viewModel: viewModel, openLibrary: openLibrary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .background(AppTheme.canvas)
        .navigationTitle(usesTabNavigation ? "Add content" : "")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isURLFieldFocused = false
                    isTextFieldFocused = false
                }
            }
        }
        #endif
        .toolbar {
            if !usesTabNavigation {
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
        }
        .navigationDestination(isPresented: $navigateToReader) {
            #if os(iOS)
            PhoneReaderView(viewModel: viewModel)
            #else
            if let url = viewModel.content?.source.webURL {
                WebReaderView(viewModel: viewModel, url: url)
            } else {
                ReaderView(viewModel: viewModel)
            }
            #endif
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
                .foregroundStyle(AppTheme.success)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(AppTheme.accentPrimarySubtle, in: Capsule())
                .overlay(Capsule().strokeBorder(AppTheme.borderAccent))
                .shadow(color: AppTheme.cardShadow, radius: 12, y: 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 24)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { viewModel.savedConfirmation = false }
                    }
                }
            }
        }
        .animation(.spring(duration: 0.4), value: viewModel.savedConfirmation)
        .onChange(of: selectedTab) { _, _ in
            isURLFieldFocused = false
            isTextFieldFocused = false
        }
    }

    // MARK: - Inputs

    private var inputPicker: some View {
        Picker("Input", selection: $selectedTab) {
            ForEach(InputTab.allCases, id: \.self) { tab in
                #if os(iOS)
                Text(tab.phoneTitle).tag(tab)
                #else
                Text(tab.rawValue).tag(tab)
                #endif
            }
        }
        .disabled(viewModel.isLoading)
    }

    private var urlInputView: some View {
        VStack(spacing: 14) {
            #if os(iOS)
            HStack {
                Text("Article links").font(.subheadline.weight(.semibold))
                Spacer()
                PasteButton(payloadType: String.self) { values in
                    urlString = values.joined(separator: "\n")
                }
                .labelStyle(.titleAndIcon)
                .controlSize(.small)
                .frame(minHeight: 44)
            }
            #endif
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 17))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                TextField("Paste article links", text: $urlString, axis: .vertical)
                    .lineLimit(2...5)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .focused($isURLFieldFocused)
                if !urlString.isEmpty {
                    Button {
                        urlString = ""
                        isURLFieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Clear links")
                }
            }
            .padding(14)
            .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isURLFieldFocused ? AppTheme.borderFocus : AppTheme.borderSubtle))

            URLInputHint(text: urlString, opensReader: openLibrary == nil)
            actionButton(importLinksTitle(URLImportParser.urls(in: urlString).count, opensReader: openLibrary == nil), icon: "bookmark.fill") {
                importLinks(urlString, fromText: false)
            }
            .disabled(URLImportParser.urls(in: urlString).isEmpty)
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
                        .foregroundStyle(AppTheme.accentPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Choose PDF")
                            .font(.subheadline.weight(.medium))
                        Text("Select a document from Files")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textMuted)
                }
                .padding(14)
                .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 12))
            }
            .foregroundStyle(AppTheme.textPrimary)
        }
    }

    private var textInputView: some View {
        VStack(spacing: 14) {
            #if os(iOS)
            HStack {
                Text("Your text").font(.subheadline.weight(.semibold))
                Spacer()
                PasteButton(payloadType: String.self) { values in
                    pastedText = values.joined(separator: "\n\n")
                }
                .labelStyle(.titleAndIcon)
                .controlSize(.small)
                .frame(minHeight: 44)
            }
            #endif
            TextEditor(text: $pastedText)
                .frame(height: 160)
                .focused($isTextFieldFocused)
                .padding(10)
                .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 12))
                .scrollContentBackground(.hidden)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isTextFieldFocused ? AppTheme.borderFocus : AppTheme.borderSubtle))
                .accessibilityLabel("Text to read aloud")
                .overlay(alignment: .topLeading) {
                    if pastedText.isEmpty {
                        Text("Paste text or article links here…")
                            .foregroundStyle(AppTheme.textMuted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }

            if !URLImportParser.urls(in: pastedText).isEmpty {
                actionButton(importLinksTitle(URLImportParser.urls(in: pastedText).count, opensReader: openLibrary == nil), icon: "bookmark.fill") {
                    importLinks(pastedText, fromText: true)
                }
            }
            if URLImportParser.urls(in: pastedText).isEmpty {
                actionButton(textImportTitle, icon: "doc.text") { loadText() }
                    .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                Button(textImportTitle, systemImage: "doc.text") { loadText() }
                    .buttonStyle(ThemeButtonStyle(primary: false))
                    .controlSize(.large)
                    .disabled(viewModel.isLoading)
            }
        }
    }

    private var textImportTitle: LocalizedStringKey {
        openLibrary == nil ? "Read pasted text" : "Save text to library"
    }

    private func actionButton(_ title: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(AppTheme.onAccent)
                } else {
                    Image(systemName: icon)
                    Text(title)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.vertical, 4)
        }
        .buttonStyle(ThemeButtonStyle(cornerRadius: 14))
        .disabled(viewModel.isLoading)
    }

    // MARK: - Actions

    private func showReader() {
        if let openReader { openReader() }
        else { navigateToReader = true }
    }

    private func showImportedContent() {
        if let openLibrary { openLibrary() }
        else { showReader() }
    }

    private func importLinks(_ value: String, fromText: Bool) {
        isURLFieldFocused = false
        isTextFieldFocused = false
        Task {
            if let result = await viewModel.importURLs(from: value), result.failures.isEmpty {
                if fromText { pastedText = "" } else { urlString = "" }
                if let openLibrary {
                    openLibrary()
                } else if let item = result.singleItem,
                   viewModel.openLibraryItem(item, preservingQueue: viewModel.currentPlaylistItemID == item.persistentModelID) {
                    showReader()
                }
            }
        }
    }

    private func loadText() {
        isTextFieldFocused = false
        Task {
            await viewModel.loadText(pastedText)
            if viewModel.errorMessage == nil, viewModel.librarySaveError == nil, viewModel.content != nil { showImportedContent() }
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
                if viewModel.errorMessage == nil, viewModel.librarySaveError == nil, viewModel.content != nil { showImportedContent() }
            }
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

#if os(iOS)
private extension HomeView.InputTab {
    var phoneTitle: LocalizedStringKey {
        switch self {
        case .url: "Link"
        case .file: "PDF"
        case .text: "Text"
        }
    }
}
#endif
