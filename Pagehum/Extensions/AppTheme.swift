import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Adaptive asset colors are shared by iPhone, Mac, and every presented screen.
/// Keep color values in Assets.xcassets; views choose a semantic role here.
enum AppTheme {
    static let canvas = Color("BgCanvas")
    static let surface = Color("BgSurface")
    static let elevated = Color("BgElevated")
    static let textPrimary = Color("TextPrimary")
    static let textSecondary = Color("TextSecondary")
    static let textMuted = Color("TextMuted")
    static let accentPrimary = Color("AccentColor")
    static let accentPrimaryFill = Color("AccentPrimaryFill")
    static let accentPrimaryHover = Color("AccentPrimaryHover")
    static let accentPrimarySubtle = Color("AccentPrimarySubtle")
    static let cta = Color("AccentCTA")
    static let ctaHover = Color("AccentCTAHover")
    static let ctaText = Color("AccentCTAText")
    static let ctaSubtle = Color("AccentCTASubtle")
    static let onAccent = Color("OnAccent")
    static let borderSubtle = Color("BorderSubtle")
    static let borderFocus = Color("BorderFocus")
    static let borderAccent = Color("BorderAccent")
    static let cardShadow = Color("CardShadow")
    static let ctaGlow = Color("CTAGlow")

    // Status also uses an icon or a label, so meaning never relies on color alone.
    static let warning = ctaText
    static let success = accentPrimary

    /// Keep the live web highlight on the same asset palette as the native reader.
    static func webHighlightColor(for scheme: ColorScheme) -> String {
        #if os(iOS)
        let color = UIColor(accentPrimarySubtle).resolvedColor(with: UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #else
        var color = NSColor.clear
        NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            color = NSColor(accentPrimarySubtle).usingColorSpace(.sRGB) ?? .clear
        }
        let red = color.redComponent, green = color.greenComponent, blue = color.blueComponent, alpha = color.alphaComponent
        #endif
        return String(format: "rgba(%d, %d, %d, %.3f)", locale: Locale(identifier: "en_US_POSIX"),
                      Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()), Double(alpha))
    }
}

extension View {
    func appTheme() -> some View {
        foregroundStyle(AppTheme.textPrimary)
            .tint(AppTheme.accentPrimary)
            .background(AppTheme.canvas.ignoresSafeArea())
            .presentationBackground(AppTheme.surface)
    }

    func themeCard(cornerRadius: CGFloat = 16, elevated: Bool = false) -> some View {
        background(elevated ? AppTheme.elevated : AppTheme.surface,
                   in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AppTheme.borderSubtle, lineWidth: 1)
            }
            .shadow(color: AppTheme.cardShadow, radius: 12, x: 0, y: 4)
    }
}

/// Primary intent is rose; secondary actions use a blue tint rather than a grey pill.
struct ThemeButtonStyle: ButtonStyle {
    enum SecondaryAccent { case blue, rose }

    var primary = true
    var cornerRadius: CGFloat = 12
    var minHeight: CGFloat = 44
    var secondaryAccent: SecondaryAccent = .blue
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let active = isEnabled && (configuration.isPressed || isHovering)
        let secondaryText = secondaryAccent == .rose ? AppTheme.ctaText : active ? AppTheme.accentPrimaryHover : AppTheme.accentPrimary
        let secondaryFill = secondaryAccent == .rose ? AppTheme.ctaSubtle : AppTheme.accentPrimarySubtle
        let secondaryBorder = secondaryAccent == .rose ? AppTheme.ctaText.opacity(active ? 0.55 : 0.2) : AppTheme.borderAccent
        return configuration.label
            .fontWeight(.semibold)
            .padding(.horizontal, 14)
            .frame(minHeight: minHeight)
            .foregroundStyle(primary ? AppTheme.onAccent : secondaryText)
            .background(primary ? (active ? AppTheme.ctaHover : AppTheme.cta) : secondaryFill,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(primary ? Color.clear : secondaryBorder, lineWidth: 1)
            }
            .shadow(color: primary && isEnabled && isHovering ? AppTheme.ctaGlow : .clear, radius: 16)
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { isHovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: active)
    }
}

struct ThemePlayButtonStyle: ButtonStyle {
    var diameter: CGFloat = 56
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let active = isEnabled && (configuration.isPressed || isHovering)
        return configuration.label
            .frame(width: diameter, height: diameter)
            .foregroundStyle(AppTheme.onAccent)
            .tint(AppTheme.onAccent)
            .background(active ? AppTheme.ctaHover : AppTheme.cta, in: Circle())
            .shadow(color: isEnabled && isHovering ? AppTheme.ctaGlow : .clear, radius: 16)
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { isHovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: active)
    }
}

/// A tinted selection surface, with the native Picker retained for VoiceOver.
struct ThemeSegmentedPicker<Selection: Hashable, Label: View>: View {
    let title: LocalizedStringKey
    let options: [Selection]
    @Binding var selection: Selection
    @ViewBuilder var label: (Selection) -> Label
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                Button { selection = option } label: {
                    label(option)
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(selection == option ? AppTheme.accentPrimary : AppTheme.textSecondary)
                        .background(selection == option ? AppTheme.accentPrimarySubtle : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selection == option ? AppTheme.borderAccent : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.borderSubtle))
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityRepresentation {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    label(option).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}
