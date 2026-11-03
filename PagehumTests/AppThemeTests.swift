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

    private func check(_ color: Color, scheme: ColorScheme, rgb: UInt32, alpha: Double) {
        #if os(iOS)
        let native = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, resolvedAlpha: CGFloat = 0
        #expect(native.getRed(&red, green: &green, blue: &blue, alpha: &resolvedAlpha))
        let components = [Double(red), Double(green), Double(blue), Double(resolvedAlpha)]
        #else
        var native = NSColor.clear
        NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            native = NSColor(color).usingColorSpace(.sRGB) ?? .clear
        }
        let components = [Double(native.redComponent), Double(native.greenComponent), Double(native.blueComponent), Double(native.alphaComponent)]
        #endif
        #expect(abs(components[3] - alpha) < 0.005)
        if alpha > 0 {
            let expected = [Double((rgb >> 16) & 255), Double((rgb >> 8) & 255), Double(rgb & 255)].map { $0 / 255 }
            for index in 0..<3 {
                #expect(abs(components[index] - expected[index]) < 0.005)
            }
        }
    }
}
