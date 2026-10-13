import SwiftUI
import SwiftData

struct LibrarySearchControls: View {
    @Binding var query: String
    @Binding var favoritesOnly: Bool
    var compact = false

    var body: some View {
        if compact {
            HStack(spacing: 12) {
                searchField
                favoritesToggle.fixedSize()
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                searchField
                favoritesToggle
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search titles, sources, and text", text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .accessibilityLabel("Search library")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .help("Clear search")
            }
        }
        .padding(compact ? 8 : 12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: compact ? 6 : 10))
    }

    private var favoritesToggle: some View {
        Toggle(isOn: $favoritesOnly) {
            Label("Starred only", systemImage: favoritesOnly ? "star.fill" : "star")
        }
        .toggleStyle(.button)
    }
}

struct LibrarySearchEmptyView: View {
    let query: String
    let favoritesOnly: Bool
    var clearFilters: () -> Void

    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ContentUnavailableView {
            Label(hasQuery ? (favoritesOnly ? "No matching starred articles" : "No matching articles") : "No starred articles", systemImage: hasQuery ? "magnifyingglass" : "star")
        } description: {
            if hasQuery {
                Text(favoritesOnly ? "Try different words or turn off Starred only." : "Try a different title, source, or phrase.")
            } else {
                Text("Tap the star beside an article to find it here.")
            }
        } actions: {
            Button("Clear filters", action: clearFilters)
        }
    }
}

struct LibraryFavoriteButton: View {
    let item: PlaylistItem
    var compact = false
    @Environment(\.modelContext) private var modelContext
    @State private var saveFailed = false

    var body: some View {
        Button {
            item.isFavorite.toggle()
            do {
                try modelContext.save()
            } catch {
                item.isFavorite.toggle()
                saveFailed = true
            }
        } label: {
            Image(systemName: item.isFavorite ? "star.fill" : "star")
                .foregroundStyle(item.isFavorite ? Color.yellow : Color.secondary)
                .frame(width: compact ? 28 : 44, height: compact ? 28 : 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.isFavorite ? "Unstar \(item.title)" : "Star \(item.title)")
        .accessibilityValue(item.isFavorite ? "Starred" : "Not starred")
        .help(item.isFavorite ? "Remove from starred" : "Add to starred")
        .alert("Couldn’t save favorite", isPresented: $saveFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please try starring this article again.")
        }
    }
}
