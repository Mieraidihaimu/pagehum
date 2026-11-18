import SwiftUI
import SwiftData
import UniformTypeIdentifiers

nonisolated struct LibraryBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw LibraryBackup.BackupError.invalidFile }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct LibraryBackupView: View {
    @ObservedObject var viewModel: ReaderModel
    @Environment(\.modelContext) private var context
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var document: LibraryBackupDocument?
    @State private var pendingBackup: LibraryBackup?
    @State private var showImportConfirmation = false
    @State private var isWorking = false
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Button(action: exportBackup) {
                    Label("Export Library Backup", systemImage: "square.and.arrow.up")
                }
                Button { showImporter = true } label: {
                    Label("Import Library Backup", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Library & History")
            } footer: {
                Text("Includes saved posts and extracted text, reading progress, favorites, completion history, and daily listening totals. Audio files, voice models, and original PDF files are excluded.")
            }
            .listRowBackground(AppTheme.surface)
            .disabled(isWorking || viewModel.isImportBusy)

            Section("iCloud Drive") {
                Text("Save your backup to iCloud Drive in the file picker, then import it on your other device.")
                Text("Automatic iCloud sync is not enabled in this build. Apple requires a paid Developer Program membership for app-level iCloud sync. Manual backups work with a free Personal Team installation.")
                    .font(.callout).foregroundStyle(AppTheme.textSecondary)
            }
            .listRowBackground(AppTheme.surface)
            Section("How Import Works") {
                Text("Import merges with your library. Matching posts keep the most recently played reading position and favorites from either library. Different versions of a post’s text are kept separately.")
                Text("For each day, the higher listening total is kept so importing the same backup again does not double-count history. Separate listening on two devices is not added together.")
                    .font(.callout).foregroundStyle(AppTheme.textSecondary)
                Text("Backups contain your saved text and browsing history. Store them somewhere you trust.")
                    .font(.callout).foregroundStyle(AppTheme.textSecondary)
            }
            .listRowBackground(AppTheme.surface)
            if isWorking { ProgressView("Preparing backup…") }
            if let message {
                Section { Text(message).foregroundStyle(AppTheme.textSecondary).accessibilityAddTraits(.updatesFrequently) }
                .listRowBackground(AppTheme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.canvas)
        .appTheme()
        .navigationTitle("Library Backup")
        .fileExporter(isPresented: $showExporter, document: document, contentType: .json,
                      defaultFilename: "Pagehum-Backup-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { result in
            switch result {
            case .success: message = "Library backup exported."
            case .failure(let error): report(error)
            }
            document = nil
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): readBackup(url)
            case .failure(let error): report(error)
            }
        }
        .confirmationDialog("Import Library Backup?", isPresented: $showImportConfirmation, titleVisibility: .visible) {
            Button("Merge into Library", action: importBackup)
            Button("Cancel", role: .cancel) { pendingBackup = nil }
        } message: {
            if let backup = pendingBackup {
                Text("Merge \(backup.articles.count) posts and \(backup.listeningHistory.count) days of listening history? Your existing posts are kept. Playback will pause during import.")
            }
        }
        .alert("Backup Failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func exportBackup() {
        message = nil
        do {
            try viewModel.saveForLibraryBackup()
            let backup = try LibraryBackupStore.snapshot(in: context)
            isWorking = true
            Task {
                defer { isWorking = false }
                do {
                    let data = try await Task.detached(priority: .userInitiated) { try backup.encoded() }.value
                    document = LibraryBackupDocument(data: data)
                    showExporter = true
                } catch { report(error) }
            }
        } catch { report(error) }
    }

    private func readBackup(_ url: URL) {
        message = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                pendingBackup = try await Task.detached(priority: .userInitiated) { try LibraryBackup.read(from: url) }.value
                showImportConfirmation = true
            } catch { report(error) }
        }
    }

    private func importBackup() {
        guard let backup = pendingBackup else { return }
        pendingBackup = nil
        do {
            viewModel.pauseForLibraryImport()
            try viewModel.saveForLibraryBackup()
            let result = try LibraryBackupStore.merge(backup, into: context)
            viewModel.didImportLibraryBackup()
            message = "Imported \(result.addedArticles) new posts, merged \(result.matchedArticles) matching posts, and merged \(result.historyDays) days of listening history."
        } catch { report(error) }
    }

    private func report(_ error: Error) {
        if (error as NSError).code != NSUserCancelledError { errorMessage = error.localizedDescription }
    }
}
