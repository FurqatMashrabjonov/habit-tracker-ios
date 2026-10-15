import Testing
@testable import HabitDomain

// The same cases as the Android app's ProgressTest, ScheduleTest, RepeatTest and CsvTest, so both
// apps agree on every streak, due day and export row.

@Suite struct DayTests {
    @Test func civilRoundTrip() {
        for (y, m, d) in [(1970, 1, 1), (2000, 2, 29), (2026, 10, 15), (2027, 2, 28), (1999, 12, 31)] {
            let day = Day(y, m, d)
            #expect(day.civil == (y, m, d))
            #expect(Day(day.description) == day)
        }
        #expect(Day(1970, 1, 1).epochDay == 0)
        #expect(Day(2026, 10, 15).epochDay == 20741) // LocalDate.of(2026, 10, 15).toEpochDay()
    }

    @Test func weekdaysAndWeeks() {
        #expect(Day(1970, 1, 1).weekday == 4) // Thursday
        #expect(Day(2026, 10, 12).weekday == 1) // Monday
        #expect(Day(2026, 10, 11).weekday == 7) // Sunday
        #expect(Day(2026, 10, 15).weekStart == Day(2026, 10, 12))
        #expect(Day(2026, 1, 31).addingMonths(1) == Day(2026, 2, 28))
        #expect(Day(2026, 12, 15).addingMonths(1) == Day(2027, 1, 15))
        #expect(Day(2024, 2, 1).lengthOfMonth == 29)
    }
}

@Suite struct ProgressTests {
    let today = Day(2026, 10, 9)
    func days(_ ago: Int...) -> Set<Day> { Set(ago.map { today - $0 }) }

    @Test func progressIsRatioAndCanExceedOne() {
        #expect(abs(progress(5, target: 8) - 0.625) < 1e-6)
        #expect(abs(progress(12, target: 8) - 1.5) < 1e-6)
        #expect(progress(3, target: 0) == 0)
    }

    @Test func currentStreakIncludesToday() { #expect(currentStreak(days(0, 1, 2, 5), today: today) == 3) }
    @Test func currentStreakNotBrokenByUnfinishedToday() { #expect(currentStreak(days(1, 2, 5), today: today) == 2) }
    @Test func singleMissIsForgiven() { #expect(currentStreak(days(0, 1, 3, 4), today: today) == 4) }

    @Test func twoMissesInARowBreakStreak() {
        #expect(currentStreak(days(0, 1, 4, 5), today: today) == 2)
        #expect(currentStreak(days(3, 4), today: today) == 0)
    }

    @Test func yesterdayMissedTodayOpenKeepsStreak() { #expect(currentStreak(days(2, 3), today: today) == 2) }

    @Test func bestStreakForgivesSingleGaps() {
        #expect(bestStreak(days(0, 1, 3, 4, 6, 9, 10)) == 5)
        #expect(bestStreak(days(0, 3)) == 1)
        #expect(bestStreak([]) == 0)
    }

    @Test func mustNotMissTodayWhenYesterdayMissed() {
        let since = today - 30
        #expect(mustNotMissToday(days(2), today: today, since: since))
        #expect(!mustNotMissToday(days(1), today: today, since: since))
        #expect(!mustNotMissToday(days(0), today: today, since: since))
        #expect(!mustNotMissToday([], today: today, since: today))
    }
}

@Suite struct ScheduleTests {
    let mon = Day(2026, 10, 12)

    @Test func encodeDecodeRoundTrip() {
        for s in [Schedule.daily, .weekdays([1, 5]), .perWeek(3)] {
            #expect(Schedule.decode(s.encode()) == s)
        }
        #expect(Schedule.weekdays([1, 3, 5]).encode() == "W1,3,5")
        #expect(Schedule.decode("") == .daily)
    }

    @Test func weekdayHabitOffDaysDontBreakStreak() {
        let s = Schedule.weekdays([1, 3, 5])
        let done = Set([14, 12, 10, 7, 5, 3].map { mon - $0 })
        let skip: Skip = { s.skip($0, done: done, today: self.mon) }
        #expect(currentStreak(done, today: mon, skip: skip) == 6)
        #expect(bestStreak(done, skip: skip) == 6)
        #expect(!mustNotMissToday(done, today: mon, since: mon - 30, skip: skip))
        #expect(s.due(mon, done: done))
        #expect(!s.due(mon + 1, done: done))
    }

    @Test func perWeekQuotaMetExcusesTheRest() {
        let s = Schedule.perWeek(3)
        let done = Set([7, 6, 5].map { mon - $0 })
        #expect(currentStreak(done, today: mon) { s.skip($0, done: done, today: self.mon) } == 3)
        #expect(s.due(mon, done: done))
        let weak: Set<Day> = [mon - 7]
        let later = mon + 7
        #expect(currentStreak(weak, today: later) { s.skip($0, done: weak, today: later) } == 0)
    }
}

@Suite struct RepeatTests {
    let sunday = Day(2026, 10, 11)

    @Test func daily() { #expect(Repeat.daily.next(after: sunday) == sunday + 1) }
    @Test func everyNDays() { #expect(Repeat.everyDays(3).next(after: sunday) == sunday + 3) }

    @Test func weeklyPicksNextMatchingDay() {
        let rule = Repeat.weekly([1, 5])
        #expect(rule.next(after: sunday) == Day(2026, 10, 12))
        #expect(rule.next(after: Day(2026, 10, 12)) == Day(2026, 10, 16))
    }

    @Test func monthlySameMonthOrNext() {
        #expect(Repeat.monthly(15).next(after: sunday) == Day(2026, 10, 15))
        #expect(Repeat.monthly(5).next(after: sunday) == Day(2026, 11, 5))
    }

    @Test func monthlyClampsToShortMonths() { #expect(Repeat.monthly(31).next(after: Day(2027, 1, 31)) == Day(2027, 2, 28)) }

    @Test func encodeRoundTrip() {
        for r in [Repeat.daily, .everyDays(3), .monthly(5), .weekly([5, 1])] {
            #expect(Repeat.decode(r.encode()) == r)
        }
        #expect(Repeat.weekly([5, 1]).encode() == "W1,5")
    }
}

@Suite struct CsvTests {
    @Test func rowsByDateThenHabitOrder_quotedWhenNeeded() {
        let d1 = Day(2026, 10, 1), d2 = Day(2026, 10, 2)
        let csv = Csv.build(
            habits: [.init(id: 2, name: "Read, then sleep", target: 1), .init(id: 1, name: "Run", target: 1)],
            entries: [.init(habitId: 1, date: d1, value: 1), .init(habitId: 2, date: d1, value: 1), .init(habitId: 1, date: d2, value: 0)],
            notes: [.init(habitId: 1, date: d2, text: "Said \"no\"")]
        )
        #expect(csv == "date,habit,done,note\r\n"
            + "2026-10-01,\"Read, then sleep\",1,\r\n"
            + "2026-10-01,Run,1,\r\n"
            + "2026-10-02,Run,0,\"Said \"\"no\"\"\"\r\n")
    }
}
