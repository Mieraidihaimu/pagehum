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
            (AppTheme.textSecondary, 0x475569, 0x94A3B8, 1, 1),
            (AppTheme.textMuted, 0x94A3B8, 0x64748B, 1, 1),
            (AppTheme.accentPrimary, 0x0284C7, 0x38BDF8, 1, 1),
            (AppTheme.accentText, 0x0369A1, 0x38BDF8, 1, 1),
            (AppTheme.accentPrimaryFill, 0x0EA5E9, 0x38BDF8, 1, 1),
            (AppTheme.accentPrimaryHover, 0x0284C7, 0x7DD3FC, 1, 1),
            (AppTheme.accentPrimarySubtle, 0x0EA5E9, 0x38BDF8, 0.10, 0.12),
            (AppTheme.cta, 0xF43F5E, 0xF43F5E, 1, 1),
            (AppTheme.ctaHover, 0xE11D48, 0xFB7185, 1, 1),
            (AppTheme.ctaText, 0xE11D48, 0xFB7185, 1, 1),
            (AppTheme.ctaSubtle, 0xF43F5E, 0xFB7185, 0.10, 0.12),
            (AppTheme.onAccent, 0xFFFFFF, 0xFFFFFF, 1, 1),
            (AppTheme.borderSubtle, 0xE2E8F0, 0x94A3B8, 1, 0.12),
            (AppTheme.borderFocus, 0x0EA5E9, 0x38BDF8, 1, 1),
            (AppTheme.borderAccent, 0x0EA5E9, 0x38BDF8, 0.18, 0.18),
            (AppTheme.cardShadow, 0x0F172A, 0x0F172A, 0.05, 0),
            (AppTheme.ctaGlow, 0xF43F5E, 0xF43F5E, 0, 0.30),
        ]
        for (color, light, dark, lightAlpha, darkAlpha) in tokens {
            check(color, scheme: .light, rgb: light, alpha: lightAlpha)
            check(color, scheme: .dark, rgb: dark, alpha: darkAlpha)
        }
    }

    @Test
    func webHighlightUsesTheNativeTintInEachAppearance() {
        #expect(AppTheme.webHighlightColor(for: .light) == "rgba(14, 165, 233, 0.100)")
        #expect(AppTheme.webHighlightColor(for: .dark) == "rgba(56, 189, 248, 0.120)")
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func browseAndReaderTextHasAtLeastFourAndAHalfToOneContrast(scheme: ColorScheme) {
        let canvas = components(of: AppTheme.canvas, scheme: scheme)
        let elevated = components(of: AppTheme.elevated, scheme: scheme)
        let tint = components(of: AppTheme.accentPrimarySubtle, scheme: scheme)
        let tintedCanvas = blend(tint, over: canvas)
        let tintedPicker = blend(tint, over: elevated)

        for token in [AppTheme.textPrimary, AppTheme.textSecondary, AppTheme.accentText] {
            let foreground = luminance(components(of: token, scheme: scheme))
            for background in [canvas, elevated, tintedCanvas, tintedPicker] {
                let backdrop = luminance(background)
                let contrast = (max(foreground, backdrop) + 0.05) / (min(foreground, backdrop) + 0.05)
                #expect(contrast >= 4.5)
            }
        }
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
