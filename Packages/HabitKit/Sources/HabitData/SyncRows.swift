import Foundation
import GRDB
import HabitDomain

/*
 * The local half of sync, the same rules as Android's Sync.kt and SyncDao.kt. The database stays the
 * source of truth; the cloud (Firestore) keeps, under users/{uid}:
 *   habits/{uuid}              the habit's fields, or deleted = true
 *   months/{uuid}_{yyyy-MM}    d = {"03": 1, …} done counts, n = {"03": "note"} ("" = note removed)
 * A run pushes rows edited after the last push (updatedAt > pushed), then pulls documents the server
 * changed since the last pull. Rows written from the cloud keep updatedAt = 0, so they aren't sent back.
 * ponytail: the last push wins per day; two phones editing the same day offline keep whichever syncs later.
 */

/// A day or note keyed by the habit's uuid, the way the cloud stores it.
public struct DayRow: Sendable, Equatable { public let habit: String; public let date: Day; public let value: Int }
public struct NoteRow: Sendable, Equatable { public let habit: String; public let date: Day; public let text: String }

/// What one push sends.
public struct Outbox: Sendable {
    public let habits: [Tracker]
    public let days: [DayRow]
    public let notes: [NoteRow]
    /// Habit uuids deleted here, and (uuid, day) notes removed here.
    public let deletedHabits: [String]
    public let deletedNotes: [(habit: String, date: Day)]

    public var isEmpty: Bool { habits.isEmpty && days.isEmpty && notes.isEmpty && deletedHabits.isEmpty && deletedNotes.isEmpty }

    /// Month documents to merge: id "uuid_yyyy-MM" → day "dd" → value / note text.
    public var months: [String: (habit: String, month: String, days: [String: Int], notes: [String: String])] {
        var out: [String: (habit: String, month: String, days: [String: Int], notes: [String: String])] = [:]
        func key(_ h: String, _ d: Day) -> (String, String, String) {
            let s = d.description
            return ("\(h)_\(s.prefix(7))", String(s.prefix(7)), String(s.suffix(2)))
        }
        for r in days {
            let (id, m, dd) = key(r.habit, r.date)
            out[id, default: (r.habit, m, [:], [:])].days[dd] = r.value
        }
        for r in notes {
            let (id, m, dd) = key(r.habit, r.date)
            out[id, default: (r.habit, m, [:], [:])].notes[dd] = r.text
        }
        for r in deletedNotes {
            let (id, m, dd) = key(r.habit, r.date)
            out[id, default: (r.habit, m, [:], [:])].notes[dd] = ""
        }
        return out
    }
}

public extension HabitStore {
    /// Everything edited after `since` (epoch ms), and the deletes still to send.
    func outbox(since: Int64) async throws -> Outbox {
        try await db.read { db in
            let habits = try Tracker.fetchAll(db, sql: "SELECT * FROM tracker WHERE updatedAt > ?", arguments: [since])
            let days = try Row.fetchAll(db, sql: "SELECT t.uuid AS habit, e.date AS date, e.value AS value FROM entry e JOIN tracker t ON t.id = e.trackerId WHERE e.updatedAt > ?", arguments: [since])
                .map { DayRow(habit: $0["habit"], date: $0["date"], value: $0["value"]) }
            let notes = try Row.fetchAll(db, sql: "SELECT t.uuid AS habit, n.date AS date, n.text AS text FROM note n JOIN tracker t ON t.id = n.trackerId WHERE n.updatedAt > ?", arguments: [since])
                .map { NoteRow(habit: $0["habit"], date: $0["date"], text: $0["text"]) }
            var deletedHabits: [String] = [], deletedNotes: [(String, Day)] = []
            for t in try Tombstone.fetchAll(db) {
                let parts = t.key.split(separator: ":", maxSplits: 2).map(String.init)
                if parts.first == "h", parts.count == 2 { deletedHabits.append(parts[1]) }
                if parts.first == "n", parts.count == 3, let d = Day(parts[2]) { deletedNotes.append((parts[1], d)) }
            }
            return Outbox(habits: habits, days: days, notes: notes, deletedHabits: deletedHabits, deletedNotes: deletedNotes)
        }
    }

    /// After a successful push: deletes made before it started are in the cloud now.
    func clearTombstones(upTo: Int64) async throws {
        try await db.write { try $0.execute(sql: "DELETE FROM tombstone WHERE deletedAt <= ?", arguments: [upTo]) }
    }

    /// After a sign-in or a restore: everything here goes up again on the next sync.
    func markAllEdited() async throws {
        try await db.write { db in
            for table in ["tracker", "entry", "note"] { try db.execute(sql: "UPDATE \(table) SET updatedAt = 1 WHERE updatedAt = 0") }
        }
    }

    /// A habit document from the cloud. Local edits made after `start` (while this run was going) win.
    /// Returns whether anything changed here.
    @discardableResult
    func applyRemoteHabit(_ remote: Tracker, deleted: Bool, start: Int64) async throws -> Bool {
        try await db.write { db in
            let local = try Tracker.filter(Column("uuid") == remote.uuid).fetchOne(db)
            if let local, local.updatedAt >= start { return false }
            if deleted {
                guard let local else { return false }
                try local.delete(db)
                return true
            }
            var row = remote
            row.id = local?.id
            row.updatedAt = 0
            if var same = local { same.updatedAt = 0; if same == row { return false } }
            try row.save(db)
            return true
        }
    }

    /// A month document from the cloud: days ("dd" → count) and notes ("dd" → text, "" = removed).
    func applyRemoteMonth(habit uuid: String, month: String, days: [String: Int], notes: [String: String], start: Int64) async throws {
        try await db.write { db in
            guard let id = try Int64.fetchOne(db, sql: "SELECT id FROM tracker WHERE uuid = ?", arguments: [uuid]) else { return }
            for (dd, value) in days {
                guard let date = Day("\(month)-\(dd)") else { continue }
                let local = try Entry.fetchOne(db, key: ["trackerId": id, "date": date.databaseValue])
                if let local, local.updatedAt >= start || local.value == value { continue }
                try Entry(trackerId: id, date: date, value: value, updatedAt: 0).save(db)
            }
            for (dd, text) in notes {
                guard let date = Day("\(month)-\(dd)") else { continue }
                let local = try Note.fetchOne(db, key: ["trackerId": id, "date": date.databaseValue])
                if let local, local.updatedAt >= start || local.text == text { continue }
                if text.isEmpty { try db.execute(sql: "DELETE FROM note WHERE trackerId = ? AND date = ?", arguments: [id, date]) }
                else { try Note(trackerId: id, date: date, text: text, updatedAt: 0).save(db) }
            }
        }
    }
}
