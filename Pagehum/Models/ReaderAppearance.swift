import Foundation
import SwiftUI

/// Per-article color scheme override for the reader.
enum ReaderAppearance: String, CaseIterable, Codable, Hashable {
    case system
    case light
    case dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var label: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    func resolvedColorScheme(system: ColorScheme) -> ColorScheme {
        colorScheme ?? system
    }
}

/// Persists per-article appearance overrides in `UserDefaults`.
struct ReaderAppearanceStore {
    static let defaultsKey = "readerAppearanceOverrides"

    static func key(for content: ReadingContent?, textID: String) -> String? {
        if let webURL = content?.source.webURL {
            return "url:\(webURL.absoluteString)"
        }
        guard !textID.isEmpty else { return nil }
        return "text:\(textID)"
    }

    static func load(from defaults: UserDefaults = .standard) -> [String: ReaderAppearance] {
        guard let raw = defaults.dictionary(forKey: defaultsKey) as? [String: String] else {
            return [:]
        }
        var result: [String: ReaderAppearance] = [:]
        for (key, value) in raw {
            if let appearance = ReaderAppearance(rawValue: value), appearance != .system {
                result[key] = appearance
            }
        }
        return result
    }

    static func save(_ overrides: [String: ReaderAppearance], to defaults: UserDefaults = .standard) {
        let raw = overrides.reduce(into: [String: String]()) { result, entry in
            if entry.value != .system {
                result[entry.key] = entry.value.rawValue
            }
        }
        if raw.isEmpty {
            defaults.removeObject(forKey: defaultsKey)
        } else {
            defaults.set(raw, forKey: defaultsKey)
        }
    }
}
