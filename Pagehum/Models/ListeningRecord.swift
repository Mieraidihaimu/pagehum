import Foundation
import SwiftData

@Model
final class ListeningRecord {
    @Attribute(.unique) var dateString: String
    var date: Date
    var secondsListened: Double

    init(date: Date = Date(), secondsListened: Double = 0) {
        self.dateString = Self.dayFormatter.string(from: date)
        self.date = Calendar.current.startOfDay(for: date)
        self.secondsListened = secondsListened
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
