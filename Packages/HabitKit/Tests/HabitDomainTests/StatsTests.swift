import Testing
@testable import HabitDomain

@Suite struct StatsTests {
    let today = Day(2026, 10, 15)

    @Test func rateCountsDueDaysOnly() {
        // Weekdays Mon/Wed/Fri since Monday Oct 5: due Oct 5, 7, 9, 12, 14 (today Thu isn't due).
        let done: Set<Day> = [Day(2026, 10, 5), Day(2026, 10, 7), Day(2026, 10, 12)]
        let s = HabitStats(done: done, created: Day(2026, 10, 5), rule: .weekdays([1, 3, 5]), today: today)
        #expect(s.completions == 3)
        #expect(abs(s.rate - 3.0 / 5.0) < 1e-9)
    }

    @Test func todayCountsOnlyOnceDone() {
        let open = HabitStats(done: [today - 1], created: today - 1, rule: .daily, today: today)
        #expect(open.rate == 1)
        let doneToday = HabitStats(done: [today - 1, today], created: today - 1, rule: .daily, today: today)
        #expect(doneToday.rate == 1)
        #expect(doneToday.current == 2)
    }

    @Test func twelveMonthsOldestFirst() {
        let s = HabitStats(done: [Day(2026, 10, 1), Day(2026, 10, 2), Day(2025, 11, 30), Day(2025, 10, 31)], created: Day(2025, 1, 1), rule: .daily, today: today)
        #expect(s.perMonth.count == 12)
        #expect(s.perMonth.first?.month == Day(2025, 11, 1))
        #expect(s.perMonth.first?.count == 1) // Oct 2025 is outside the window
        #expect(s.perMonth.last?.month == Day(2026, 10, 1))
        #expect(s.perMonth.last?.count == 2)
    }
}
