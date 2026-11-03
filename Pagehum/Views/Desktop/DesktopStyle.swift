#if os(macOS)
import AppKit
import SwiftUI

enum DesktopStyle {
    static let canvas = AppTheme.canvas
    static let sidebar = AppTheme.surface
    static let panel = AppTheme.surface
    static let border = AppTheme.borderSubtle
    static let text = AppTheme.textPrimary
    static let secondary = AppTheme.textSecondary
    static let accent = AppTheme.accentPrimary
    static let action = AppTheme.cta
    static let speeds: [Float] = [0.75, 1, 1.25, 1.5, 2, 2.25, 2.5, 3]

    static func speedLabel(_ speed: Float) -> String {
        "\(speed.formatted(.number.precision(.fractionLength(0...2))))×"
    }

    static func voiceLabel(_ voice: String) -> String {
        if let systemName = SystemSpeechEngine.displayName(for: voice) { return systemName }
        let parts = voice.split(separator: "_")
        guard parts.count == 2 else { return voice }
        let language = voice.first == "a" ? "English (US)" : voice.first == "b" ? "English (UK)" : String(parts[0]).uppercased()
        return "\(parts[1].capitalized) · \(language)"
    }
}

struct DesktopButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let active = isEnabled && (configuration.isPressed || isHovering)
        return configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .foregroundStyle(primary ? AppTheme.onAccent : active ? AppTheme.accentPrimaryHover : DesktopStyle.accent)
            .background(primary ? (active ? AppTheme.ctaHover : AppTheme.cta) : AppTheme.accentPrimarySubtle, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(primary ? .clear : AppTheme.borderAccent))
            .shadow(color: primary && isEnabled && isHovering ? AppTheme.ctaGlow : .clear, radius: 16)
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { isHovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: active)
    }
}

struct DesktopPage<Content: View>: View {
    var width: CGFloat = 680
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: width, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

struct DesktopHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 30, weight: .medium)).tracking(-0.7)
            Text(subtitle).foregroundStyle(DesktopStyle.secondary)
        }
        .padding(.bottom, 28)
    }
}
#endif
