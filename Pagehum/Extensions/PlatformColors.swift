import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    static var platformGroupedBackground: Color {
        AppTheme.canvas
    }

    static var secondaryGroupedBackground: Color {
        AppTheme.surface
    }

    static var tertiaryFill: Color {
        AppTheme.elevated
    }

    static var platformGray: Color {
        AppTheme.textMuted
    }
}
