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
                guard h.rule.due(day, done: done), let at = date(day, time), at > now else { continue }
                let progress = h.target > 1 && offset == 0 ? "\(value)/\(h.target)" : nil
                let body = [h.cue, progress].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  ·  ")
                out.append(ReminderPlan(id: "h:\(h.uuid):\(day.epochDay)", title: h.name, body: body, at: at, isTask: false,
                                        info: ["habit": id, "day": Int64(day.epochDay)]))
            }
        }
        return Array(out.prefix(budget))
    }
}
