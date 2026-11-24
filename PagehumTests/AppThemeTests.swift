import SwiftUI
import Testing
@testable import Pagehum
#if os(iOS)
import UIKit
#else
import AppKit
#endif

@MainActor
struct AppThemeTests {
    @Test
    func semanticAssetsResolveToBothPalettes() {
        let tokens: [(Color, UInt32, UInt32, Double, Double)] = [
            (AppTheme.canvas, 0xFFFFFF, 0x0B0F17, 1, 1),
            (AppTheme.surface, 0xF8FAFC, 0x161F30, 1, 1),
            (AppTheme.elevated, 0xF1F5F9, 0x1E293B, 1, 1),
            (AppTheme.textPrimary, 0x0F172A, 0xF8FAFC, 1, 1),
            (AppTheme.textSecondary, 0x475569, 0xA3B3C6, 1, 1),
            (AppTheme.textMuted, 0x94A3B8, 0x64748B, 1, 1),
            (AppTheme.accentPrimary, 0x0284C7, 0x38BDF8, 1, 1),
            (AppTheme.accentText, 0x0369A1, 0x38BDF8, 1, 1),
            (AppTheme.accentPrimaryFill, 0x0EA5E9, 0x38BDF8, 1, 1),
            (AppTheme.accentPrimaryHover, 0x0284C7, 0x7DD3FC, 1, 1),
            (AppTheme.accentPrimarySubtle, 0x0EA5E9, 0x38BDF8, 0.10, 0.12),
            (AppTheme.cta, 0xE11D48, 0xF43F5E, 1, 1),
            (AppTheme.ctaHover, 0xBE123C, 0xFB7185, 1, 1),
            (AppTheme.ctaText, 0xE11D48, 0xFB7185, 1, 1),
            (AppTheme.ctaSubtle, 0xF43F5E, 0xFB7185, 0.10, 0.12),
            (AppTheme.onAccent, 0xFFFFFF, 0xFFFFFF, 1, 1),
            (AppTheme.borderSubtle, 0xE2E8F0, 0x94A3B8, 1, 0.12),
            (AppTheme.borderFocus, 0x0EA5E9, 0x38BDF8, 1, 1),
            (AppTheme.borderAccent, 0x0EA5E9, 0x38BDF8, 0.18, 0.18),
            (AppTheme.cardShadow, 0x0F172A, 0x0F172A, 0.05, 0),
            (AppTheme.ctaGlow, 0xF43F5E, 0xF43F5E, 0, 0.30),
            (AppTheme.favorite, 0xD97706, 0xFBBF24, 1, 1),
            (AppTheme.favoriteSubtle, 0xF59E0B, 0xF59E0B, 0.12, 0.16),
            (AppTheme.favoriteText, 0x92400E, 0xFDE68A, 1, 1),
            (AppTheme.destructive, 0xDC2626, 0xF87171, 1, 1),
            (AppTheme.destructiveSubtle, 0xEF4444, 0xEF4444, 0.10, 0.15),
            (AppTheme.destructiveText, 0xB91C1C, 0xFCA5A5, 1, 1),
            (AppTheme.readerSentenceBg, 0x0EA5E9, 0x38BDF8, 0.09, 0.10),
            (AppTheme.readerWordBg, 0x0EA5E9, 0x38BDF8, 0.22, 0.26),
            (AppTheme.readerWordText, 0x0C4A6E, 0xF8FAFC, 1, 1),
            (AppTheme.playerSurface, 0xFFFFFF, 0x121A29, 0.94, 1),
            (AppTheme.playerBorder, 0xE2E8F0, 0x94A3B8, 1, 0.18),
            (AppTheme.darkTopHighlight, 0xFFFFFF, 0xFFFFFF, 0, 0.08),
            (AppTheme.floatingShadow, 0x0F172A, 0x000000, 0.08, 0.40),
        ]
        for (color, light, dark, lightAlpha, darkAlpha) in tokens {
            check(color, scheme: .light, rgb: light, alpha: lightAlpha)
            check(color, scheme: .dark, rgb: dark, alpha: darkAlpha)
        }
    }

    @Test
    func webHighlightUsesTheNativeTintInEachAppearance() {
        #expect(AppTheme.webHighlightColor(for: .light) == "rgba(14, 165, 233, 0.090)")
        #expect(AppTheme.webHighlightColor(for: .dark) == "rgba(56, 189, 248, 0.100)")
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func browseAndReaderTextHasAtLeastFourAndAHalfToOneContrast(scheme: ColorScheme) {
        let canvas = components(of: AppTheme.canvas, scheme: scheme)
        let surface = components(of: AppTheme.surface, scheme: scheme)
        let elevated = components(of: AppTheme.elevated, scheme: scheme)
        let tint = components(of: AppTheme.accentPrimarySubtle, scheme: scheme)
        let tintedCanvas = blend(tint, over: canvas)
        let tintedPicker = blend(tint, over: elevated)

        for token in [AppTheme.textPrimary, AppTheme.textSecondary, AppTheme.accentText] {
            let foreground = luminance(components(of: token, scheme: scheme))
            for background in [canvas, surface, elevated, tintedCanvas, tintedPicker] {
                let backdrop = luminance(background)
                let contrast = (max(foreground, backdrop) + 0.05) / (min(foreground, backdrop) + 0.05)
                #expect(contrast >= 4.5)
            }
        }

        // Semantic badges & active spoken word contrast checks
        let favPill = blend(components(of: AppTheme.favoriteSubtle, scheme: scheme), over: surface)
        let favFg = luminance(components(of: AppTheme.favoriteText, scheme: scheme))
        let favBg = luminance(favPill)
        #expect((max(favFg, favBg) + 0.05) / (min(favFg, favBg) + 0.05) >= 4.5)

        let errPill = blend(components(of: AppTheme.destructiveSubtle, scheme: scheme), over: surface)
        let errFg = luminance(components(of: AppTheme.destructiveText, scheme: scheme))
        let errBg = luminance(errPill)
        #expect((max(errFg, errBg) + 0.05) / (min(errFg, errBg) + 0.05) >= 4.5)

        let wordPill = blend(components(of: AppTheme.readerWordBg, scheme: scheme), over: canvas)
        let wordFg = luminance(components(of: AppTheme.readerWordText, scheme: scheme))
        let wordBg = luminance(wordPill)
        #expect((max(wordFg, wordBg) + 0.05) / (min(wordFg, wordBg) + 0.05) >= 4.5)
    }

    @Test
    func lightModeCtaClearsContrastWithWhiteLabel() {
        let fg = luminance(components(of: AppTheme.onAccent, scheme: .light))
        let bg = luminance(components(of: AppTheme.cta, scheme: .light))
        #expect((max(fg, bg) + 0.05) / (min(fg, bg) + 0.05) >= 4.5)
    }

    private func blend(_ color: [Double], over background: [Double]) -> [Double] {
        zip(color.prefix(3), background.prefix(3)).map { $0 * color[3] + $1 * (1 - color[3]) }
    }

    private func luminance(_ components: [Double]) -> Double {
        let linear = components.prefix(3).map { value in
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }

    private func components(of color: Color, scheme: ColorScheme) -> [Double] {
        #if os(iOS)
        let native = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, resolvedAlpha: CGFloat = 0
        #expect(native.getRed(&red, green: &green, blue: &blue, alpha: &resolvedAlpha))
        return [Double(red), Double(green), Double(blue), Double(resolvedAlpha)]
        #else
        var native = NSColor.clear
        NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            native = NSColor(color).usingColorSpace(.sRGB) ?? .clear
        }
        return [Double(native.redComponent), Double(native.greenComponent), Double(native.blueComponent), Double(native.alphaComponent)]
        #endif
    }

    private func check(_ color: Color, scheme: ColorScheme, rgb: UInt32, alpha: Double) {
        let components = components(of: color, scheme: scheme)
        #expect(abs(components[3] - alpha) < 0.005)
        if alpha > 0 {
            let expected = [Double((rgb >> 16) & 255), Double((rgb >> 8) & 255), Double(rgb & 255)].map { $0 / 255 }
            for index in 0..<3 {
                #expect(abs(components[index] - expected[index]) < 0.005)
            }
        }
    }
}
