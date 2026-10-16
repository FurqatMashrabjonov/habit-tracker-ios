/// One habit's numbers for the Statistics screen (Android's StatsViewModel.stats).
public struct HabitStats: Equatable, Sendable {
    public let completions: Int
    /// Done days / due days since the habit started (off days don't count, today only once done).
    public let rate: Double
    public let current: Int
    public let best: Int
    /// Done days per month for the last twelve months, oldest first; the day is the 1st of the month.
    public let perMonth: [(month: Day, count: Int)]

    public static func == (a: HabitStats, b: HabitStats) -> Bool {
        a.completions == b.completions && a.rate == b.rate && a.current == b.current && a.best == b.best
            && a.perMonth.map(\.count) == b.perMonth.map(\.count) && a.perMonth.map(\.month) == b.perMonth.map(\.month)
    }

    public init(done: Set<Day>, created: Day, rule: Schedule, today: Day, rest: Set<Day> = []) {
        let skip: Skip = { rule.skip($0, done: done, today: today, rest: rest) }
        let since = min(done.min() ?? created, created)
        var due = 0
        var d = since
        while d <= today {
            if done.contains(d) || (!skip(d) && d < today) { due += 1 }
            d = d + 1
        }
        completions = done.count
        rate = due == 0 ? 0 : Double(done.count) / Double(due)
        current = currentStreak(done, today: today, skip: skip)
        best = bestStreak(done, skip: skip)
        let thisMonth = today.withDay(1)
        perMonth = (0..<12).reversed().map { back in
            let m = thisMonth.addingMonths(-back)
            return (m, done.filter { $0.year == m.year && $0.month == m.month }.count)
        }
    }
}
