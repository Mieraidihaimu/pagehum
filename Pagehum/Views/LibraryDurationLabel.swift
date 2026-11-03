import SwiftUI

/// A text-only estimate. Cells never prepare speech or tokenize articles for duration.
struct LibraryDurationLabel: View {
    let item: PlaylistItem
    var speed: Float = 1

    var body: some View {
        let characters = item.libraryCharacterCount
        Text(ListeningQueue.durationLabel(characters: characters, speed: speed, compact: true))
            .font(.caption.monospacedDigit())
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(1)
            .fixedSize()
            .help("Estimated listening time at the current playback speed, based on article text.")
            .accessibilityLabel("Estimated listening time")
            .accessibilityValue(ListeningQueue.durationLabel(characters: characters, speed: speed))
    }
}
