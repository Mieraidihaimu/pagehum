import Foundation

enum LegacyPlaybackOffsetMigration {
    static func resolve(
        fullText: String,
        legacySentenceIndex: Int,
        isCompleted: Bool,
        splitProse: (String) -> [String]
    ) -> Int {
        if isCompleted { return fullText.utf16.count }

        let segmented = ArticleSegmenter.segment(fullText, splitProse: splitProse)
        guard !segmented.sentences.isEmpty else { return 0 }

        let index = max(legacySentenceIndex, 0)
        guard index < segmented.sentences.count else { return fullText.utf16.count }
        return segmented.sentenceStartOffsetsUTF16[index]
    }

    @discardableResult
    static func migrate(
        items: [PlaylistItem],
        splitProse: (String) -> [String]
    ) -> Bool {
        var changed = false
        for item in items where item.playbackTextOffset == nil {
            let isCompleted = item.progressPercent >= 1
                || item.status == PlaylistItem.Status.completed.rawValue
            item.playbackTextOffset = resolve(
                fullText: item.fullText,
                legacySentenceIndex: item.lastSentenceIndex,
                isCompleted: isCompleted,
                splitProse: splitProse
            )
            changed = true
        }
        return changed
    }
}