import SwiftUI
import SwiftData

struct StatsView: View {
    @Query(sort: \ListeningRecord.date, order: .reverse) private var records: [ListeningRecord]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                totalTimeCard
                streaksCard
                contributionGraphCard
            }
            .padding(20)
        }
        .background(Color.platformGroupedBackground)
        .navigationTitle("Listening Stats")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }

    // MARK: - Total Time

    private var totalTimeCard: some View {
        let totalSeconds = records.reduce(0.0) { $0 + $1.secondsListened }
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60

        return VStack(spacing: 8) {
            Image(systemName: "headphones.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.cyan)
                .symbolRenderingMode(.hierarchical)

            if hours > 0 {
                Text("\(hours)h \(minutes)m")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
            } else {
                Text("\(minutes)m")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
            }

            Text("Total Listening Time")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    // MARK: - Streaks

    private var streaksCard: some View {
        let (current, longest) = calculateStreaks()

        return HStack(spacing: 16) {
            streakItem(value: current, label: "Current Streak", icon: "flame.fill", color: .orange)
            streakItem(value: longest, label: "Longest Streak", icon: "trophy.fill", color: .yellow)
        }
    }

    private func streakItem(value: Int, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text("\(value)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value == 1 ? "day" : "days")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private func calculateStreaks() -> (current: Int, longest: Int) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let activeDays = Set(records.map { calendar.startOfDay(for: $0.date) })

        var currentStreak = 0
        var day = today
        // Allow today to be missing (day isn't over yet)
        if !activeDays.contains(day) {
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        while activeDays.contains(day) {
            currentStreak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }

        var longestStreak = 0
        var streak = 0
        var prevDay: Date?
        for d in activeDays.sorted() {
            if let prev = prevDay, calendar.dateComponents([.day], from: prev, to: d).day == 1 {
                streak += 1
            } else {
                streak = 1
            }
            longestStreak = max(longestStreak, streak)
            prevDay = d
        }

        return (currentStreak, longestStreak)
    }

    // MARK: - Contribution Graph

    private var contributionGraphCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Activity")
                .font(.headline)

            ContributionGridView(records: records)

            HStack(spacing: 4) {
                Text("Less")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(legendColor(level))
                        .frame(width: 12, height: 12)
                }
                Text("More")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private func legendColor(_ level: Int) -> Color {
        switch level {
        case 0: return Color.platformGray
        case 1: return Color.accentColor.opacity(0.25)
        case 2: return Color.accentColor.opacity(0.5)
        case 3: return Color.accentColor.opacity(0.75)
        default: return Color.accentColor
        }
    }
}

// MARK: - Contribution Grid

private struct ContributionGridView: View {
    let records: [ListeningRecord]

    private let weeks = 26
    private let cellSize: CGFloat = 12
    private let cellSpacing: CGFloat = 3

    var body: some View {
        let grid = buildGrid()
        let maxSeconds = grid.flatMap { $0 }.max() ?? 1

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: cellSpacing) {
                ForEach(0..<grid.count, id: \.self) { weekIndex in
                    VStack(spacing: cellSpacing) {
                        ForEach(0..<grid[weekIndex].count, id: \.self) { dayIndex in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(colorForSeconds(grid[weekIndex][dayIndex], max: maxSeconds))
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
        }
        .defaultScrollAnchor(.trailing)
    }

    private func buildGrid() -> [[Double]] {
        let calendar = Calendar.current
        let today = Date()
        let currentWeekday = calendar.component(.weekday, from: today)
        let daysBack = (currentWeekday - 1) + (weeks - 1) * 7
        guard let startDate = calendar.date(byAdding: .day, value: -daysBack, to: today) else { return [] }

        var lookup: [String: Double] = [:]
        for record in records {
            lookup[record.dateString] = record.secondsListened
        }

        var result: [[Double]] = []
        var currentDate = startDate
        for _ in 0..<weeks {
            var week: [Double] = []
            for _ in 0..<7 {
                if currentDate <= today {
                    let key = ListeningRecord.dayFormatter.string(from: currentDate)
                    week.append(lookup[key] ?? 0)
                }
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
            }
            result.append(week)
        }
        return result
    }

    private func colorForSeconds(_ seconds: Double, max: Double) -> Color {
        guard seconds > 0 else { return Color.platformGray }
        let ratio = seconds / max
        switch ratio {
        case ..<0.25: return Color.accentColor.opacity(0.25)
        case ..<0.50: return Color.accentColor.opacity(0.5)
        case ..<0.75: return Color.accentColor.opacity(0.75)
        default: return Color.accentColor
        }
    }
}
