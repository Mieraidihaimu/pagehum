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
    @State private var selectedTab: InputTab = .url
    @State private var urlString = ""
    @State private var pastedText = ""
    @State private var showFilePicker = false
    @State private var navigateToReader = false
    @FocusState private var isURLFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Minimized Brand Header
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        Image(systemName: "waveform")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pagehum")
                            .font(.system(size: 20, weight: .bold, design: .rounded))

                        if viewModel.isModelLoaded {
                            Text("Read anything aloud")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.mini)
                                Text("Loading model…")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)

                // Input selector
                VStack(spacing: 16) {
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
                .padding(18)
                .background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.04), radius: 8, y: 3)

                TechBlogQuickImportView(viewModel: viewModel)

                URLImportStatusView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
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
                if !urlString.isEmpty {
                    Button {
                        urlString = ""
                        isURLFieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Clear links")
                }
            }
            .padding(14)
            .background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isURLFieldFocused ? Color.accentColor : Color.primary.opacity(0.12)))

            URLInputHint(text: urlString)
            actionButton(importLinksTitle(URLImportParser.urls(in: urlString).count), icon: "bookmark.fill") {
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
                actionButton(importLinksTitle(URLImportParser.urls(in: pastedText).count), icon: "bookmark.fill") {
                    importLinks(pastedText, fromText: true)
                }
            }
            if URLImportParser.urls(in: pastedText).isEmpty {
                actionButton("Read pasted text", icon: "doc.text") { loadText() }
                    .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                Button("Read pasted text", systemImage: "doc.text") { loadText() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(viewModel.isLoading)
            }
        }
    }

    private func actionButton(_ title: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
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

    private func importLinks(_ value: String, fromText: Bool) {
        Task {
            if let result = await viewModel.importURLs(from: value), result.failures.isEmpty {
                if fromText { pastedText = "" } else { urlString = "" }
                if let item = result.singleItem,
                   viewModel.openLibraryItem(item, preservingQueue: viewModel.currentPlaylistItemID == item.persistentModelID) {
                    navigateToReader = true
                }
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
