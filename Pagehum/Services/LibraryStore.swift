import Combine
import SwiftData

/// A failed disk store must never silently become a temporary, empty library.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var container: ModelContainer?
    @Published private(set) var errorMessage: String?
    private let openContainer: () throws -> ModelContainer

    init(openContainer: @escaping () throws -> ModelContainer = {
        try ModelContainer(for: Schema([PlaylistItem.self, ListeningRecord.self]))
    }) {
        self.openContainer = openContainer
        retry()
    }

    func retry() {
        guard container == nil else { return }
        do {
            container = try openContainer()
            errorMessage = nil
        } catch {
            errorMessage = "Your saved library could not be opened. Your files have been kept. Free up storage if needed, then try again."
        }
    }
}
