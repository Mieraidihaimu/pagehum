import SwiftUI

enum PlaybackSpeed {
    static let playerPresets: [Float] = [1, 1.5, 2, 2.5, 3]
    static let settingsOptions = Array(stride(from: Float(0.75), through: 3, by: 0.25))

    static func label(_ speed: Float) -> String {
        "\(speed.formatted())×"
    }
}

struct PlayerSpeedOptions: View {
    @Binding var speed: Float

    var body: some View {
        ForEach(PlaybackSpeed.playerPresets.reversed(), id: \.self) { preset in
            Button {
                speed = preset
            } label: {
                if speed == preset {
                    Label(PlaybackSpeed.label(preset), systemImage: "checkmark")
                } else {
                    Text(PlaybackSpeed.label(preset))
                }
            }
            .accessibilityAddTraits(speed == preset ? .isSelected : [])
        }
    }
}
