/// One habit's numbers for the Statistics screen (Android's StatsViewModel.stats).
public struct HabitStats: Equatable, Sendable {
    public let completions: Int
    /// Done days / due days since the habit started (off days don't count, today only once done).
    public let rate: Double
    public let current: Int
    public let best: Int
    /// Done days per month for the last twelve months, oldest first; the day is the 1st of the month.
    public let perMonth: [(month: Day, count: Int)]
    /// The same rate over the last 30 days: a slip costs a few percent, not the whole run.
    public let momentum: Double
    /// Momentum over the 30 days before those, to show which way it's going; nil while the habit is
    /// too new to have had a due day back then.
    public let momentumBefore: Double?
    /// Rate per weekday, Monday first; nil where the habit was never due (an off day).
    public let byWeekday: [Double?]
    /// First day counted: the earlier of the first done day and the day the habit was made.
    public let since: Day

    public static func == (a: HabitStats, b: HabitStats) -> Bool {
        a.completions == b.completions && a.rate == b.rate && a.current == b.current && a.best == b.best
            && a.perMonth.map(\.count) == b.perMonth.map(\.count) && a.perMonth.map(\.month) == b.perMonth.map(\.month)
            && a.momentum == b.momentum && a.momentumBefore == b.momentumBefore && a.byWeekday == b.byWeekday && a.since == b.since
    }

    public init(done: Set<Day>, created: Day, rule: Schedule, today: Day, rest: Set<Day> = []) {
        let skip: Skip = { rule.skip($0, done: done, today: today, rest: rest) }
        let since = min(done.min() ?? created, created)
        /// Done and due days in a range, the rate's rule: off days don't count, today only once done.
        func count(_ from: Day, _ to: Day) -> (done: Int, due: Int) {
            var hit = 0, due = 0
            var d = max(from, since)
            while d <= to {
                if done.contains(d) { hit += 1; due += 1 } else if !skip(d) && d < today { due += 1 }
                d = d + 1
            }
            return (hit, due)
        }
        func share(_ c: (done: Int, due: Int)) -> Double { c.due == 0 ? 0 : Double(c.done) / Double(c.due) }
        self.since = since
        completions = done.count
        rate = share(count(since, today))
        momentum = share(count(today - 29, today))
        let before = count(today - 59, today - 30)
        momentumBefore = before.due == 0 ? nil : share(before)
        var weekdayDone = [Int](repeating: 0, count: 7), weekdayDue = [Int](repeating: 0, count: 7)
        var d = since
        while d <= today {
            let w = d.weekday - 1
            if done.contains(d) { weekdayDone[w] += 1; weekdayDue[w] += 1 } else if !skip(d) && d < today { weekdayDue[w] += 1 }
            d = d + 1
        }
        byWeekday = (0..<7).map { weekdayDue[$0] == 0 ? nil : Double(weekdayDone[$0]) / Double(weekdayDue[$0]) }
        current = currentStreak(done, today: today, skip: skip)
        best = bestStreak(done, skip: skip)
        let thisMonth = today.withDay(1)
        perMonth = (0..<12).reversed().map { back in
            let m = thisMonth.addingMonths(-back)
            return (m, done.filter { $0.year == m.year && $0.month == m.month }.count)
        }
    }
}

/// The last 30 days' rate on its own, for the home screen: done days over due days, today only once done.
public func momentum(_ done: Set<Day>, today: Day, since: Day, skip: Skip) -> Double {
    var hit = 0, due = 0
    var d = max(today - 29, since)
    while d <= today {
        if done.contains(d) { hit += 1; due += 1 } else if !skip(d) && d < today { due += 1 }
        d = d + 1
    }
    return due == 0 ? 0 : Double(hit) / Double(due)
}
