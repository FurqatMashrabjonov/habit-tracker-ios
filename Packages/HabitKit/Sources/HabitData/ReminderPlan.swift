import Foundation
import GRDB
import HabitDomain

/// One reminder to schedule: which notification, when, and what it says. The app turns these into
/// notification requests; keeping the choice here lets it be tested without a phone.
public struct ReminderPlan: Sendable, Equatable {
    public let id: String
    public let title: String
    public let body: String
    public let at: Date
    public let isTask: Bool
    /// "habit" + "day" (epoch day), or "task": the ids the Done button needs.
    public let info: [String: Int64]

    /// iOS keeps 64 pending notifications per app; this leaves room for snoozes.
    public static let budget = 56

    /// Tasks once at their due time; habits on each of the next days they are due (fewer days when
    /// many habits remind), skipping today once it's done. Only times after `now`.
    public static func all(_ db: Database, today: Day, now: Date, calendar: Calendar) throws -> [ReminderPlan] {
        func date(_ day: Day, _ time: ClockTime) -> Date? {
            calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: time.hour, minute: time.minute))
        }
        var out: [ReminderPlan] = []
        for t in try Task.fetchAll(db, sql: "SELECT * FROM task WHERE done = 0 AND dueTime IS NOT NULL ORDER BY dueDate, dueTime") {
            guard let id = t.id, let time = t.dueTime, let at = date(t.dueDate ?? today, time), at > now else { continue }
            out.append(ReminderPlan(id: "t:\(id)", title: t.title, body: time.description, at: at, isTask: true, info: ["task": id]))
        }
        out = Array(out.prefix(budget / 2))
        let habits = try Tracker.fetchAll(db, sql: "SELECT * FROM tracker WHERE reminder IS NOT NULL AND archived = 0 ORDER BY sortOrder, id")
        guard !habits.isEmpty else { return out }
        let days = max(1, min(7, (budget - out.count) / habits.count))
        for h in habits {
            guard let id = h.id, let time = h.reminder else { continue }
            let done = try HabitStore.doneDays(in: db, of: h, from: today.weekStart, to: today)
            let value = try Int.fetchOne(db, sql: "SELECT value FROM entry WHERE trackerId = ? AND date = ?", arguments: [id, today]) ?? 0
            for offset in 0..<days {
                let day = today + offset
                // ponytail: later days assume nothing more gets done; any check rebuilds the whole set.
                guard h.rule.due(day, done: done), !(offset == 0 && value == Entry.rest), let at = date(day, time), at > now else { continue }
                let progress = h.target > 1 && offset == 0 ? "\(value)/\(h.target)" : nil
                let body = [h.cue, progress].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  ·  ")
                out.append(ReminderPlan(id: "h:\(h.uuid):\(day.epochDay)", title: h.name, body: body, at: at, isTask: false,
                                        info: ["habit": id, "day": Int64(day.epochDay)]))
            }
        }
        return Array(out.prefix(budget))
    }

    /// Pro's evening check-in, one per day for the next `days`: the habits still open then, or none at all
    /// on a day nothing is. Later days assume nothing more gets done; any check rebuilds them (the widget
    /// redoes today's).
    public static func nudges(_ db: Database, today: Day, at time: ClockTime, now: Date, calendar: Calendar, days: Int) throws -> [ReminderPlan] {
        let habits = try Tracker.fetchAll(db, sql: "SELECT * FROM tracker WHERE archived = 0 ORDER BY sortOrder, id")
        var out: [ReminderPlan] = []
        for offset in 0..<days {
            let day = today + offset
            guard let at = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: time.hour, minute: time.minute)),
                  at > now else { continue }
            var open: [String] = []
            for h in habits {
                guard let id = h.id else { continue }
                let value = offset == 0 ? try HabitStore.value(in: db, of: id, on: day) : 0
                let done = try HabitStore.doneDays(in: db, of: h, from: day.weekStart, to: today)
                if value != Entry.rest && !h.isDone(value) && h.rule.due(day, done: done) { open.append(h.name) }
            }
            guard !open.isEmpty else { continue }
            let (title, body) = open.count == 1 ? (open[0], "Still open today") : ("\(open.count) habits still open today", open.joined(separator: ", "))
            out.append(ReminderPlan(id: "n:\(day.epochDay)", title: title, body: body, at: at, isTask: false, info: [:]))
        }
        return out
    }
}
