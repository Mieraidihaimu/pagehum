#if os(macOS)
import SwiftUI

enum DesktopStyle {
    static let canvas = Color(red: 0.125, green: 0.129, blue: 0.133)
    static let sidebar = Color(red: 0.106, green: 0.110, blue: 0.118)
    static let panel = Color(red: 0.161, green: 0.169, blue: 0.180)
    static let border = Color(red: 0.239, green: 0.251, blue: 0.267)
    static let text = Color(red: 0.949, green: 0.941, blue: 0.922)
    static let secondary = Color(red: 0.686, green: 0.698, blue: 0.722)
    static let accent = Color(red: 0.510, green: 0.722, blue: 1)
    static let action = Color(red: 0.035, green: 0.420, blue: 0.851)
    static let speeds: [Float] = [0.75, 1, 1.25, 1.5, 2, 2.25, 2.5, 3]

    static func speedLabel(_ speed: Float) -> String {
        "\(speed.formatted(.number.precision(.fractionLength(0...2))))×"
    }

    static func voiceLabel(_ voice: String) -> String {
        let parts = voice.split(separator: "_")
        guard parts.count == 2 else { return voice }
        let language = voice.first == "a" ? "English (US)" : voice.first == "b" ? "English (UK)" : String(parts[0]).uppercased()
        return "\(parts[1].capitalized) · \(language)"
    }
}

struct DesktopButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .foregroundStyle(primary ? .white : DesktopStyle.text)
            .background(primary ? DesktopStyle.action : DesktopStyle.panel, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(primary ? .clear : DesktopStyle.border))
            .brightness(configuration.isPressed ? -0.08 : 0)
            .opacity(isEnabled ? 1 : 0.45)
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
