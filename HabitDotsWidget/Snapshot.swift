import Foundation
import GRDB
import HabitData
import HabitDomain

/// A habit as a widget draws it, read once per timeline.
struct HabitSnap: Hashable {
    let id: Int64
    let name: String
    let icon: String
    let target: Int
    let value: Int
    let progress: [Day: Double]
    let streak: Int
    /// Not due today (an off day, or the week's quota met).
    let off: Bool
    /// Off days of the last weeks, for the faint cells.
    let offDays: Set<Day>
    let monthDone: Int
    let monthDue: Int

    var done: Bool { value >= target }
    var partial: Double { done ? 0 : Double(value) / Double(max(target, 1)) }
}

enum Snapshot {
    static let weeks = 26

    static func store() -> HabitStore? { try? HabitStore(path: Shared.databasePath) }

    static func habits(_ db: Database, today: Day) throws -> [HabitSnap] {
        let from = today - 7 * weeks
        let entries = try Entry.filter(Column("date") >= from - 7).fetchAll(db)
        let byHabit = Dictionary(grouping: entries, by: \.trackerId)
        return try HabitStore.trackers(in: db).map { t in snap(t, entries: byHabit[t.id ?? -1] ?? [], today: today, from: from) }
    }

    static func habit(_ db: Database, id: Int64, today: Day) throws -> HabitSnap? {
        guard let t = try Tracker.fetchOne(db, key: id) else { return nil }
        let entries = try Entry.filter(Column("trackerId") == id && Column("date") >= today - 7 * weeks - 7).fetchAll(db)
        return snap(t, entries: entries, today: today, from: today - 7 * weeks)
    }

    private static func snap(_ t: Tracker, entries: [Entry], today: Day, from: Day) -> HabitSnap {
        var progress: [Day: Double] = [:]
        for e in entries { progress[e.date] = min(Double(e.value) / Double(t.target), 1) }
        let done = Set(entries.filter { t.isDone($0.value) }.map(\.date))
        let rule = t.rule
        let rest = entries.restDays
        let skip: Skip = { rule.skip($0, done: done, today: today, rest: rest) }
        let month = Array(today.withDay(1)...today)
        let due = month.filter { done.contains($0) || !skip($0) }
        return HabitSnap(
            id: t.id ?? 0, name: t.name, icon: t.icon, target: t.target,
            value: max(entries.first { $0.date == today }?.value ?? 0, 0),
            progress: progress,
            streak: currentStreak(done, today: today, skip: skip),
            off: (!rule.due(today, done: done) || rest.contains(today)) && !done.contains(today),
            offDays: Set((from...today).filter { !done.contains($0) && skip($0) && $0 != today }),
            monthDone: due.filter { done.contains($0) }.count,
            monthDue: due.count
        )
    }

    // ---- Examples for the widget gallery and placeholders ----

    static func sample(today: Day) -> [HabitSnap] {
        [("Read 20 pages", "book-open", 1, 1, 0.85), ("Drink water", "drop", 8, 5, 0.75), ("Morning run", "person-simple-run", 1, 0, 0.55),
         ("Meditate", "flower-lotus", 1, 0, 0.7)].enumerated().map { i, s in
            var seed = UInt64(i + 7)
            func roll() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
            var progress: [Day: Double] = [:]
            for ago in 1...(7 * weeks) where roll() < s.4 { progress[today - ago] = 1 }
            if s.3 > 0 { progress[today] = min(Double(s.3) / Double(s.2), 1) }
            let done = Set(progress.filter { $0.value >= 1 }.keys)
            return HabitSnap(id: Int64(-i - 1), name: s.0, icon: s.1, target: s.2, value: s.3, progress: progress,
                             streak: currentStreak(done, today: today), off: false, offDays: [], monthDone: 9, monthDue: today.day)
        }
    }

    static func sampleTasks(today: Day) -> [Task] {
        [("Call mom", ClockTime(18, 0)), ("Pay rent", nil), ("Buy groceries", nil), ("Book dentist", nil)].enumerated().map { i, s in
            var t = Task(title: s.0)
            t.id = Int64(-i - 1)
            t.dueDate = today
            t.dueTime = s.1
            return t
        }
    }
}
