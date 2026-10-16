import Foundation
import GRDB
import HabitDomain

/// The database and every write to it, like the Android app's DAOs. Reads happen through `reader`
/// (one-off) or `observe` (live). The app and the widget open the same file in the App Group.
public final class HabitStore: Sendable {
    public let db: DatabasePool

    /// Opens (and migrates) the database at `path`; `nil` opens an in-memory one for tests.
    public init(path: String?) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        // nil (tests): a throwaway file, since a pool needs WAL and WAL needs a real file.
        let file = path ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db").path
        db = try DatabasePool(path: file, configuration: config)
        try Schema.migrator.migrate(db)
    }

    public var reader: DatabaseReader { db }

    /// Re-runs `fetch` whenever a table it read changes (also writes from the widget process).
    public func observe<T: Sendable>(_ fetch: @escaping @Sendable (Database) throws -> T) -> AsyncValueObservation<T> {
        ValueObservation.tracking(fetch).values(in: db)
    }

    // --- Habits -----------------------------------------------------------------------------------

    public func trackers(includeArchived: Bool = false) async throws -> [Tracker] {
        try await db.read { try Self.trackers(in: $0, includeArchived: includeArchived) }
    }

    public static func trackers(in db: Database, includeArchived: Bool = false) throws -> [Tracker] {
        try Tracker.fetchAll(db, sql: "SELECT * FROM tracker WHERE archived = 0 OR ? ORDER BY archived, sortOrder, id", arguments: [includeArchived])
    }

    /// Every local edit goes through here, so it carries the time sync needs.
    @discardableResult
    public func save(_ tracker: Tracker) async throws -> Tracker {
        var t = tracker
        t.updatedAt = Clock.nowMillis()
        if t.id == nil { t.sortOrder = try await db.read { try Int.fetchOne($0, sql: "SELECT COALESCE(MAX(sortOrder), -1) + 1 FROM tracker") ?? 0 } }
        let row = t
        return try await db.write { db in var r = row; return try r.saved(db) }
    }

    /// Raw write: keeps `updatedAt` (0 for rows from the cloud).
    public func put(_ tracker: Tracker) async throws { try await db.write { var t = tracker; try t.save($0) } }

    public func reorder(_ ids: [Int64]) async throws {
        let now = Clock.nowMillis()
        try await db.write { db in
            for (order, id) in ids.enumerated() {
                try db.execute(sql: "UPDATE tracker SET sortOrder = ?, updatedAt = ? WHERE id = ? AND sortOrder != ?", arguments: [order, now, id, order])
            }
        }
    }

    // --- Days -------------------------------------------------------------------------------------

    public func value(of trackerId: Int64, on date: Day) async throws -> Int {
        try await db.read { try Self.value(in: $0, of: trackerId, on: date) }
    }

    static func value(in db: Database, of trackerId: Int64, on date: Day) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT value FROM entry WHERE trackerId = ? AND date = ?", arguments: [trackerId, date]) ?? 0
    }

    public func entries(of trackerId: Int64) async throws -> [Entry] {
        try await db.read { try Entry.filter(Column("trackerId") == trackerId).fetchAll($0) }
    }

    /// Days the habit reached its target between `from` and `to`.
    public static func doneDays(in db: Database, of tracker: Tracker, from: Day, to: Day) throws -> Set<Day> {
        Set(try Day.fetchAll(db, sql: "SELECT date FROM entry WHERE trackerId = ? AND value >= ? AND date BETWEEN ? AND ?",
                             arguments: [tracker.id, tracker.target, from, to]))
    }

    public func setValue(_ value: Int, of trackerId: Int64, on date: Day) async throws {
        try await db.write { try Self.put(Entry(trackerId: trackerId, date: date, value: max(value, 0)), in: $0) }
    }

    /// Rest day <-> nothing.
    public func toggleRest(_ trackerId: Int64, on date: Day) async throws {
        try await db.write { db in
            let rest = try Self.value(in: db, of: trackerId, on: date) == Entry.rest
            try Self.put(Entry(trackerId: trackerId, date: date, value: rest ? 0 : Entry.rest), in: db)
        }
    }

    /// One-tap action: +1 until done, then back to 0 (a once-a-day habit just toggles).
    public func quick(_ tracker: Tracker, on date: Day) async throws {
        guard let id = tracker.id else { return }
        try await db.write { db in try Self.quick(in: db, tracker, id: id, on: date) }
    }

    /// The widget's one write, in the same transaction shape as the app's.
    public static func quick(in db: Database, _ tracker: Tracker, id: Int64, on date: Day) throws {
        let v = max(try value(in: db, of: id, on: date), 0) // a rest day counts as 0
        switch tracker.type {
        case .boolean: try put(Entry(trackerId: id, date: date, value: tracker.isDone(v) ? 0 : v + 1), in: db)
        case .count: try put(Entry(trackerId: id, date: date, value: v + 1), in: db)
        case .duration: try put(Entry(trackerId: id, date: date, value: v + 5), in: db)
        }
    }

    static func put(_ entry: Entry, in db: Database) throws { var e = entry; e.updatedAt = Clock.nowMillis(); try e.save(db) }

    // --- Notes ------------------------------------------------------------------------------------

    public func notes(of trackerId: Int64) async throws -> [Note] {
        try await db.read { try Note.filter(Column("trackerId") == trackerId).order(Column("date").desc).fetchAll($0) }
    }

    public func saveNote(_ note: Note) async throws {
        var n = note
        n.updatedAt = Clock.nowMillis()
        let row = n
        try await db.write { try row.save($0) }
    }

    public func deleteNote(of trackerId: Int64, on date: Day) async throws {
        try await db.write { db in
            guard let uuid = try String.fetchOne(db, sql: "SELECT uuid FROM tracker WHERE id = ?", arguments: [trackerId]) else { return }
            try Tombstone(key: "n:\(uuid):\(date)").save(db)
            try db.execute(sql: "DELETE FROM note WHERE trackerId = ? AND date = ?", arguments: [trackerId, date])
        }
    }

    // --- Trash ------------------------------------------------------------------------------------

    /// Days and notes go with it (foreign keys cascade); the tombstone carries the delete to the cloud.
    /// A copy goes to the trash first, for Undo and Settings > Recently deleted.
    public func delete(_ tracker: Tracker) async throws -> TrashedHabit? {
        guard let id = tracker.id else { return nil }
        return try await db.write { db in
            let entries = try Entry.filter(Column("trackerId") == id).fetchAll(db)
            let notes = try Note.filter(Column("trackerId") == id).fetchAll(db)
            let item = TrashedHabit(uuid: tracker.uuid, name: tracker.name, deletedAt: Clock.nowMillis(),
                                    data: try Trash.snapshot(tracker, entries: entries, notes: notes))
            try item.save(db)
            try Tombstone(key: "h:\(tracker.uuid)").save(db)
            try tracker.delete(db)
            return item
        }
    }

    /// Back as it was, with fresh edit times so sync uploads it again. Returns the restored habit.
    @discardableResult
    public func restore(_ item: TrashedHabit) async throws -> Tracker {
        try await db.write { db in
            let (tracker, days, notes) = try Trash.unpack(item)
            var t = tracker
            t.updatedAt = Clock.nowMillis()
            try t.save(db) // keeps its old local id, so a widget pointed at it keeps working
            let id = t.id!
            for e in days(id) { try Self.put(e, in: db) }
            for n in notes(id) { var x = n; x.updatedAt = Clock.nowMillis(); try x.save(db) }
            try db.execute(sql: "DELETE FROM tombstone WHERE `key` = ?", arguments: ["h:\(item.uuid)"])
            try db.execute(sql: "DELETE FROM trash WHERE uuid = ?", arguments: [item.uuid])
            return t
        }
    }

    public func trash() async throws -> [TrashedHabit] {
        try await db.read { try TrashedHabit.order(Column("deletedAt").desc).fetchAll($0) }
    }

    public func purgeTrash(olderThan days: Int = Trash.keepDays) async throws {
        try await db.write { try $0.execute(sql: "DELETE FROM trash WHERE deletedAt < ?", arguments: [Clock.nowMillis() - Int64(days) * 86_400_000]) }
    }

    // --- Tasks ------------------------------------------------------------------------------------

    public static func openTasks(in db: Database) throws -> [Task] {
        try Task.fetchAll(db, sql: "SELECT * FROM task WHERE done = 0 ORDER BY dueDate IS NULL, dueDate, dueTime IS NULL, dueTime, id")
    }

    @discardableResult
    public func save(_ task: Task) async throws -> Task { try await db.write { var t = task; return try t.saved($0) } }

    public func delete(_ task: Task) async throws { _ = try await db.write { try task.delete($0) } }

    /// One-off: mark done. Recurring: move to the next occurrence after today (missed ones are skipped).
    @discardableResult
    public func complete(_ task: Task, today: Day) async throws -> Task {
        var next = task
        if let rule = Repeat.decode(task.repeat) {
            next.dueDate = rule.next(after: max(task.dueDate ?? today, today))
        } else {
            next.done = true
            next.completedAt = Clock.nowMillis()
        }
        return try await save(next)
    }

    // --- Backup -----------------------------------------------------------------------------------

    /// Whole-database copy, write-ahead log folded in, the same file Android writes and reads.
    public func export(to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        // SQLite's online backup: a consistent copy even while the app's live queries read.
        let copy = try DatabaseQueue(path: url.path)
        try db.backup(to: copy)
        // One self-contained file (rollback journal), like the copy Android's Backup writes and reads.
        try copy.writeWithoutTransaction { try $0.execute(sql: "PRAGMA journal_mode = DELETE") }
        try copy.close()
        for suffix in ["-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
    }

    /// True when `url` is a HabitDots backup this app can open (schema version 8, from either platform).
    public static func isBackup(_ url: URL) -> Bool {
        // Not read-only: a WAL-mode file needs its -shm to open. Callers pass a private copy of the picked file.
        guard FileManager.default.fileExists(atPath: url.path), let q = try? DatabaseQueue(path: url.path) else { return false }
        return (try? q.read { try Schema.accepts($0) }) ?? false
    }
}
