/// One habit's history, as the overview needs it: the same inputs as `HabitStats`, plus how it's named.
public struct HabitHistory: Sendable {
    public let name: String
    public let icon: String
    public let done: Set<Day>
    public let rest: Set<Day>
    public let created: Day
    public let rule: Schedule
    public let streak: Int
    public init(name: String, icon: String, done: Set<Day>, rest: Set<Day>, created: Day, rule: Schedule, streak: Int) {
        self.name = name; self.icon = icon; self.done = done; self.rest = rest; self.created = created; self.rule = rule; self.streak = streak
    }
}

/// All habits together, for the Statistics page's "All" view. Few numbers, each one a feeling:
/// today's ring, this week against last, perfect days, every habit's momentum, a year of dots,
/// and a handful of sentences the dots add up to.
public struct OverviewStats: Sendable {
    /// Habits due today and how many of them are done (a counted habit counts once).
    public let todayDue: Int
    public let todayDone: Int
    /// Monday to today: done over due, as a share, and the same for the whole of last week.
    public let week: Double
    public let lastWeek: Double?
    /// Each of the last seven days (oldest first): done over due, nil when nothing was due.
    public let weekDays: [Double?]
    /// The last 30 days (oldest first): true where every due habit was done and at least one was due.
    public let perfectDays: [Bool]
    /// Whole weeks (Monday to Sunday) in the last twelve that were perfect every day.
    public let perfectWeeks: Int
    public let bestStreak: Int
    /// Per habit: its 30-day momentum, the 30 before, and the last 30 days as done flags (oldest first).
    public let habits: [HabitLine]
    /// The last 365 days (oldest first): done over due, nil when nothing was due.
    public let year: [Double?]
    public let insights: [String]

    public struct HabitLine: Sendable, Equatable {
        public let name: String
        public let icon: String
        public let momentum: Double
        public let before: Double?
        public let streak: Int
        public let days: [Bool]
    }

    /// Long weekday names, Monday first, for the insight sentences.
    public static let weekdayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    public init(_ habits: [HabitHistory], today: Day, weekdays: [String] = OverviewStats.weekdayNames) {
        let skips: [(HabitHistory, Skip)] = habits.map { h in (h, { d in h.rule.skip(d, done: h.done, today: today, rest: h.rest) }) }
        /// For one day: how many habits were due and how many of those were done. Today counts a
        /// habit as due only once done, like the rate (an unfinished day isn't a miss yet).
        func dayCount(_ d: Day) -> (done: Int, due: Int) {
            var done = 0, due = 0
            for (h, skip) in skips where d >= h.created || h.done.contains(d) {
                if h.done.contains(d) { done += 1; due += 1 } else if !skip(d) && d < today { due += 1 }
            }
            return (done, due)
        }
        func share(_ c: (done: Int, due: Int)) -> Double? { c.due == 0 ? nil : Double(c.done) / Double(c.due) }
        func total(_ from: Day, _ to: Day) -> (done: Int, due: Int) {
            var done = 0, due = 0
            var d = from
            while d <= to { let c = dayCount(d); done += c.done; due += c.due; d = d + 1 }
            return (done, due)
        }
        // Today: every habit that is due by its schedule, done or not.
        var due = 0, done = 0
        for (h, skip) in skips where today >= h.created {
            if h.done.contains(today) { done += 1; due += 1 } else if !skip(today) { due += 1 }
        }
        todayDue = due; todayDone = done
        let monday = today.weekStart
        week = share(total(monday, today)) ?? 0
        lastWeek = share(total(monday - 7, monday - 1))
        // The strip's last cell is today as it stands, unfinished habits included: "3 of 5 so far".
        weekDays = (0..<6).map { share(dayCount(today - (6 - $0))) } + [due == 0 ? nil : Double(done) / Double(due)]
        perfectDays = (0..<30).map { let c = dayCount(today - (29 - $0)); return c.due > 0 && c.done == c.due }
        perfectWeeks = (1...12).filter { back in
            let start = monday - 7 * back
            return (0..<7).allSatisfy { let c = dayCount(start + $0); return c.due > 0 && c.done == c.due }
        }.count
        bestStreak = habits.map(\.streak).max() ?? 0
        self.habits = skips.map { h, skip in
            let since = min(h.created, h.done.min() ?? h.created)
            let before = HabitStats.momentum(h.done, from: today - 59, to: today - 30, since: since, today: today, skip: skip)
            return HabitLine(name: h.name, icon: h.icon,
                             momentum: HabitStats.momentum(h.done, from: today - 29, to: today, since: since, today: today, skip: skip) ?? 0,
                             before: before, streak: h.streak,
                             days: (0..<30).map { h.done.contains(today - (29 - $0)) })
        }
        year = (0..<365).map { share(dayCount(today - (364 - $0))) }
        insights = Self.insights(skips, lines: self.habits, today: today, weekdays: weekdays)
    }

    /// A few sentences the dots add up to. Each has a bar to clear, so a quiet month says nothing
    /// and a new user sees no card at all.
    static func insights(_ skips: [(HabitHistory, Skip)], lines: [HabitLine], today: Day, weekdays: [String]) -> [String] {
        var out: [String] = []
        // 1. A weekday pattern: the habit whose strongest and weakest days are 20 points apart.
        var gap: (name: String, best: Int, bestRate: Int, worst: Int, worstRate: Int, diff: Double)? = nil
        for (h, skip) in skips where today - max(h.created, h.done.min() ?? h.created) >= 28 {
            let s = HabitStats(done: h.done, created: h.created, rule: h.rule, today: today, rest: h.rest)
            let rates = s.byWeekday.enumerated().compactMap { i, r in r.map { (i, $0) } }
            guard let hi = rates.max(by: { $0.1 < $1.1 }), let lo = rates.min(by: { $0.1 < $1.1 }), hi.1 - lo.1 >= 0.2 else { continue }
            if gap == nil || hi.1 - lo.1 > gap!.diff {
                gap = (h.name, hi.0, Int((hi.1 * 100).rounded()), lo.0, Int((lo.1 * 100).rounded()), hi.1 - lo.1)
            }
        }
        if let g = gap {
            out.append("You keep \(g.name) on \(g.bestRate)% of \(weekdays[g.best])s, but \(g.worstRate)% of \(weekdays[g.worst])s.")
        }
        // 2. The biggest move this month, up or down, of 8 points or more.
        if let m = lines.compactMap({ l -> (HabitLine, Int)? in l.before.map { (l, Int(((l.momentum - $0) * 100).rounded())) } })
            .filter({ abs($0.1) >= 8 }).max(by: { abs($0.1) < abs($1.1) }) {
            out.append(m.1 > 0 ? "\(m.0.name) is up \(m.1) points on the 30 days before." : "\(m.0.name) slipped \(-m.1) points this month.")
        }
        // 3. Two habits that happen together: on days with the first, the second is done 70%+ of the time.
        var pair: (a: String, b: String, rate: Int)? = nil
        for (a, _) in skips { for (b, _) in skips where a.name != b.name {
            let withA = a.done.filter { $0 >= max(a.created, b.created) && $0 <= today }
            guard withA.count >= 20 else { continue }
            let both = withA.filter { b.done.contains($0) }.count
            let rate = Double(both) / Double(withA.count)
            // Only worth saying when it's more than b's own rate: a real pull, not two daily habits.
            let bRate = Double(b.done.filter { $0 >= max(a.created, b.created) && $0 <= today }.count) / Double(today - max(a.created, b.created) + 1)
            if rate >= 0.7, rate - bRate >= 0.15, pair == nil || rate > Double(pair!.rate) / 100 {
                pair = (a.name, b.name, Int((rate * 100).rounded()))
            }
        } }
        if let p = pair { out.append("On days you do \(p.a), you also do \(p.b) \(p.rate)% of the time.") }
        // 4. The next milestone for the longest streak.
        if let top = lines.max(by: { $0.streak < $1.streak }), top.streak >= 3,
           let next = [7, 30, 66, 100, 200, 365].first(where: { $0 > top.streak }) {
            out.append("\(next - top.streak) days to a \(next)-day streak on \(top.name).")
        }
        return out
    }
}

extension HabitStats {
    /// Done over due days in a range, the rate's rule; nil when nothing was due.
    static func momentum(_ done: Set<Day>, from: Day, to: Day, since: Day, today: Day, skip: Skip) -> Double? {
        var hit = 0, due = 0
        var d = max(from, since)
        while d <= to {
            if done.contains(d) { hit += 1; due += 1 } else if !skip(d) && d < today { due += 1 }
            d = d + 1
        }
        return due == 0 ? nil : Double(hit) / Double(due)
    }
}
