import Foundation
import SwiftData

/// One row per article, including saves made with other voices and removed library items.
enum OfflineAudioLibrary {
    struct Entry: Identifiable {
        let id: String
        let item: PlaylistItem?
        let records: [OfflineAudioStore.Record]
        let displayRecord: OfflineAudioStore.Record

        var title: String { item?.title ?? displayRecord.request.title }
        var isReady: Bool { records.contains { $0.isReady } }
        var canPlay: Bool { isReady && item != nil }
    }

    static func entries(records: [OfflineAudioStore.Record], items: [PlaylistItem], preferredVoice: String) -> [Entry] {
        let itemsByText = Dictionary(grouping: items.filter { !$0.isDeleted }) {
            OfflineAudioRequest.textIdentifier($0.fullText)
        }
        return Dictionary(grouping: records, by: { $0.request.textID }).map { textID, records in
            let sorted = records.sorted {
                if $0.isReady != $1.isReady { return $0.isReady }
                let lhsPreferred = $0.request.voice == preferredVoice
                let rhsPreferred = $1.request.voice == preferredVoice
                if lhsPreferred != rhsPreferred { return lhsPreferred }
                return $0.request.id < $1.request.id
            }
            return Entry(id: textID, item: itemsByText[textID]?.first, records: sorted, displayRecord: sorted[0])
        }.sorted {
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}
