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

    @Test func restDaysKeepTheStreakAndLeaveTheRate() {
        // Done the last 2 days and 6-8 days ago; days 3-5 ago were rest days (sick).
        let done = Set([1, 2, 6, 7, 8].map { today - $0 })
        let rest = Set([3, 4, 5].map { today - $0 })
        let s = HabitStats(done: done, created: today - 8, rule: .daily, today: today, rest: rest)
        #expect(s.current == 5)
        #expect(s.rate == 1)
        #expect(HabitStats(done: done, created: today - 8, rule: .daily, today: today).current == 2)
    }

    @Test func todayCountsOnlyOnceDone() {
        let open = HabitStats(done: [today - 1], created: today - 1, rule: .daily, today: today)
        #expect(open.rate == 1)
        let doneToday = HabitStats(done: [today - 1, today], created: today - 1, rule: .daily, today: today)
        #expect(doneToday.rate == 1)
        #expect(doneToday.current == 2)
    }

    @Test func momentumIsTheLastThirtyDays() {
        // Daily for 60 days: every day before the last 30 done, 24 of the last 30 (today included).
        let done = Set((30..<60).map { today - $0 } + (0..<24).map { today - $0 })
        let s = HabitStats(done: done, created: today - 59, rule: .daily, today: today)
        #expect(abs(s.momentum - 24.0 / 30.0) < 1e-9)
        #expect(s.momentumBefore == 1)
        #expect(s.since == today - 59)
    }

    @Test func momentumStartsWhenTheHabitDoes() {
        // Made 10 days ago and done every day since: a full score, not 10 of 30.
        let done = Set((0..<10).map { today - $0 })
        let s = HabitStats(done: done, created: today - 9, rule: .daily, today: today)
        #expect(s.momentum == 1)
        #expect(s.momentumBefore == nil)
    }

    @Test func weekdayRatesSkipOffDays() {
        // Mon/Wed/Fri for two weeks from Monday Oct 5 (today is Thursday Oct 15): Mondays both done,
        // Wednesdays one of two, Fridays none of one; Tuesday was never due.
        let done: Set<Day> = [Day(2026, 10, 5), Day(2026, 10, 12), Day(2026, 10, 7)]
        let s = HabitStats(done: done, created: Day(2026, 10, 5), rule: .weekdays([1, 3, 5]), today: today)
        #expect(s.byWeekday[0] == 1)
        #expect(s.byWeekday[1] == nil)
        #expect(s.byWeekday[2] == 0.5)
        #expect(s.byWeekday[4] == 0)
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
