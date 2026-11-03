import SwiftUI
import SwiftData

struct LibrarySearchControls: View {
    @Binding var query: String
    @Binding var favoritesOnly: Bool
    var compact = false
    @FocusState private var isSearching: Bool

    var body: some View {
        #if os(iOS)
        HStack(spacing: 8) {
            searchField
            Button { favoritesOnly.toggle() } label: {
                Image(systemName: favoritesOnly ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(AppTheme.ctaText)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.ctaSubtle, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(favoritesOnly ? AppTheme.ctaText : .clear))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Starred only")
            .accessibilityValue(favoritesOnly ? "On" : "Off")
            .accessibilityAddTraits(favoritesOnly ? .isSelected : [])
        }
        #else
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
        #endif
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.textSecondary)
            TextField("Search titles, sources, and text", text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .accessibilityLabel("Search library")
                .focused($isSearching)
                .onSubmit { isSearching = false }
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                #endif
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(AppTheme.textSecondary)
                        #if os(iOS)
                        .frame(width: 44, height: 44)
                        #endif
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .help("Clear search")
            }
        }
        #if os(iOS)
        .frame(minHeight: 44)
        .padding(.horizontal, 12)
        #else
        .padding(compact ? 8 : 12)
        #endif
        .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: compact ? 6 : 10))
    }

    private var favoritesToggle: some View {
        Button { favoritesOnly.toggle() } label: {
            Label("Starred only", systemImage: favoritesOnly ? "star.fill" : "star")
        }
        .buttonStyle(ThemeButtonStyle(primary: false, minHeight: 36, secondaryAccent: .rose))
        .accessibilityValue(favoritesOnly ? "On" : "Off")
        .accessibilityAddTraits(favoritesOnly ? .isSelected : [])
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
                .foregroundStyle(AppTheme.ctaText)
                #if os(iOS)
                .frame(width: 44, height: 44)
                #else
                .frame(width: compact ? 28 : 44, height: compact ? 28 : 44)
                #endif
                .background(item.isFavorite ? AppTheme.ctaSubtle : .clear, in: Circle())
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
