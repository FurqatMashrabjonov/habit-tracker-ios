import Testing
@testable import HabitDomain

@Suite struct OverviewTests {
    let today = Day(2026, 10, 18) // a Sunday
    func habit(_ name: String, done: [Int], created: Int = 60, rule: Schedule = .daily, streak: Int = 0) -> HabitHistory {
        HabitHistory(name: name, icon: "x", done: Set(done.map { today - $0 }), rest: [], created: today - created, rule: rule, streak: streak)
    }

    @Test func todayAndWeek() {
        // Two daily habits: A done every day of the week, B done Mon–Wed only (Sun = today, not done).
        let a = habit("A", done: Array(0...13), streak: 14)
        let b = habit("B", done: [4, 5, 6] + Array(7...13), streak: 0)
        let o = OverviewStats([a, b], today: today)
        #expect(o.todayDue == 2 && o.todayDone == 1)
        // Mon–Sun: A 7/7, B 3/6 (today not due until done) → 10/13.
        #expect(abs(o.week - 10.0 / 13.0) < 1e-9)
        #expect(o.lastWeek == 1)
        #expect(o.weekDays.last == 0.5)
        #expect(o.bestStreak == 14)
        #expect(o.habits.count == 2)
    }

    @Test func perfectDaysAndWeeks() {
        let a = habit("A", done: Array(1...40))
        let b = habit("B", done: Array(1...40))
        let o = OverviewStats([a, b], today: today)
        // Today isn't done, so not perfect; the 29 days before are.
        #expect(o.perfectDays.count == 30 && o.perfectDays.last == false && o.perfectDays.dropLast().allSatisfy { $0 })
        // Last week (Mon Oct 5 – Sun Oct 11) and the one before are perfect; this week isn't a whole week yet.
        #expect(o.perfectWeeks >= 2)
    }

    @Test func insightsStayQuietWithoutData() {
        let a = habit("A", done: [1, 2], created: 3)
        #expect(OverviewStats([a], today: today).insights.isEmpty)
    }

    @Test func weekdayInsight() {
        // Done every day except Saturdays for 12 weeks.
        let days = (1...84).filter { (today - $0).weekday != 6 }
        let a = habit("Read", done: days, created: 90, streak: 1)
        let o = OverviewStats([a], today: today)
        #expect(o.insights.contains { $0.contains("Read") && $0.contains("Saturday") })
    }

    @Test func yearHasADayPerSlot() {
        let o = OverviewStats([habit("A", done: [0, 1, 2])], today: today)
        #expect(o.year.count == 365 && o.year.last == 1)
    }
}

@Suite struct GapTests {
    @Test func longestGapCountsDueDaysOnly() {
        let today = Day(2026, 10, 18)
        // Done every day except a 3-day hole ending 10 days ago, and a 1-day hole 2 days ago.
        let done = Set((1...40).filter { !(10...12).contains($0) && $0 != 2 }.map { today - $0 })
        let s = HabitStats(done: done, created: today - 40, rule: .daily, today: today)
        #expect(s.longestGap == HabitStats.Gap(days: 3, end: today - 10))
        // On a Mon/Wed/Fri habit, a missed Wednesday between done Mon and Fri is a 1-day gap, not 3.
        let mwf = HabitStats(done: [today - 6, today - 2], created: today - 6, rule: .weekdays([1, 3, 5]), today: today)
        #expect(mwf.longestGap?.days == 1)
    }
}
