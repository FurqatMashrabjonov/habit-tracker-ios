import Foundation
import Testing
import HabitDomain
@testable import HabitData

@Suite struct ReminderPlanTests {
    let today = Day(2026, 10, 15) // a Thursday
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Tashkent")!; return c }
    func at(_ day: Day, _ h: Int, _ m: Int) -> Date { calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: h, minute: m))! }

    func plans(_ s: HabitStore, now: Date) async throws -> [ReminderPlan] {
        let (today, cal) = (today, calendar)
        return try await s.db.read { try ReminderPlan.all($0, today: today, now: now, calendar: cal) }
    }

    @Test func dailyHabitRemindsEachOfTheNextDaysUntilDone() async throws {
        let s = try HabitStore(path: nil)
        var t = Tracker(name: "Read", icon: "book-open")
        t.reminder = ClockTime(21, 0)
        t.cue = "Before bed"
        t = try await s.save(t)

        let morning = try await plans(s, now: at(today, 9, 0))
        #expect(morning.count == 7)
        #expect(morning.first?.at == at(today, 21, 0))
        #expect(morning.first?.body == "Before bed")
        #expect(morning.first?.info == ["habit": t.id!, "day": Int64(today.epochDay)])

        // Done today: today's goes, tomorrow's stays.
        try await s.quick(t, on: today)
        #expect(try await plans(s, now: at(today, 9, 0)).first?.at == at(today + 1, 21, 0))
        // Past today's time: from tomorrow.
        try await s.quick(t, on: today)
        #expect(try await plans(s, now: at(today, 22, 0)).first?.at == at(today + 1, 21, 0))
    }

    @Test func offDaysAndArchivedHabitsDontRemind() async throws {
        let s = try HabitStore(path: nil)
        var gym = Tracker(name: "Gym", icon: "barbell")
        gym.reminder = ClockTime(7, 0)
        gym.schedule = Schedule.weekdays([1, 3, 5]).encode()
        try await s.save(gym)
        var old = Tracker(name: "Old", icon: "x")
        old.reminder = ClockTime(7, 0)
        old.archived = true
        try await s.save(old)
        // Thursday 06:00: Fri, Mon, Wed of the next seven days.
        let days = try await plans(s, now: at(today, 6, 0)).map { calendar.component(.weekday, from: $0.at) }
        #expect(days == [6, 2, 4]) // Calendar: Sunday = 1
    }

    @Test func tasksOnceAndTheBudgetHolds() async throws {
        let s = try HabitStore(path: nil)
        var call = Task(title: "Call mom")
        call.dueDate = today
        call.dueTime = ClockTime(18, 0)
        call = try await s.save(call)
        var past = Task(title: "Gone")
        past.dueDate = today - 1
        past.dueTime = ClockTime(9, 0)
        try await s.save(past)
        for i in 0..<20 {
            var t = Tracker(name: "H\(i)", icon: "drop")
            t.reminder = ClockTime(20, 0)
            try await s.save(t)
        }
        let all = try await plans(s, now: at(today, 9, 0))
        #expect(all.first == ReminderPlan(id: "t:\(call.id!)", title: "Call mom", body: "18:00", at: at(today, 18, 0), isTask: true, info: ["task": call.id!]))
        #expect(all.count <= ReminderPlan.budget)
        #expect(all.filter { !$0.isTask }.count == 20 * 2) // 55 left / 20 habits = 2 days each
    }

    @Test func eveningCheckInListsOnlyWhatIsStillOpen() async throws {
        let s = try HabitStore(path: nil)
        let read = try await s.save(Tracker(name: "Read", icon: "book-open"))
        _ = try await s.save(Tracker(name: "Run", icon: "person-simple-run"))
        let (today, cal) = (today, calendar)
        func nudges() async throws -> [ReminderPlan] {
            let now = at(today, 9, 0)
            return try await s.db.read { try ReminderPlan.nudges($0, today: today, at: ClockTime(21, 0), now: now, calendar: cal, days: 2) }
        }
        var n = try await nudges()
        #expect(n.first?.title == "2 habits still open today")
        #expect(n.first?.body == "Read, Run")
        #expect(n.first?.at == at(today, 21, 0))
        try await s.quick(read, on: today)
        n = try await nudges()
        #expect(n.first?.title == "Run")
        #expect(n.first?.body == "Still open today")
        // Everything done today: no check-in tonight, tomorrow's stays.
        let run = try await s.trackers().first { $0.name == "Run" }!
        try await s.quick(run, on: today)
        n = try await nudges()
        #expect(n.map(\.id) == ["n:\(today.epochDay + 1)"])
    }
}
