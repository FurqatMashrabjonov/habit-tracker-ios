import Foundation
import GRDB
import Testing
import HabitDomain
@testable import HabitData

@Suite struct StoreTests {
    let today = Day(2026, 10, 15)

    func store() throws -> HabitStore { try HabitStore(path: nil) }

    @Test func schemaMatchesRoomVersion8() throws {
        let s = try store()
        try s.db.read { db in
            #expect(try Int32.fetchOne(db, sql: "PRAGMA user_version") == 8)
            #expect(try String.fetchOne(db, sql: "SELECT identity_hash FROM room_master_table WHERE id = 42") == Schema.roomIdentityHash)
            let cols = try db.columns(in: "tracker").map(\.name)
            #expect(cols == ["id", "name", "icon", "color", "type", "dailyTarget", "unit", "direction", "sortOrder", "archived", "createdAt", "cue", "identity", "reminder", "schedule", "uuid", "updatedAt"])
            #expect(try Schema.accepts(db))
        }
    }

    @Test func quickTogglesAndCounts() async throws {
        let s = try store()
        let read = try await s.save(Tracker(name: "Read", icon: "book-open"))
        try await s.quick(read, on: today)
        #expect(try await s.value(of: read.id!, on: today) == 1)
        try await s.quick(read, on: today)
        #expect(try await s.value(of: read.id!, on: today) == 0)

        var water = Tracker(name: "Water", icon: "drop")
        water.dailyTarget = 3
        water = try await s.save(water)
        for _ in 0..<3 { try await s.quick(water, on: today) }
        #expect(try await s.value(of: water.id!, on: today) == 3)
        try await s.quick(water, on: today) // done: back to 0
        #expect(try await s.value(of: water.id!, on: today) == 0)
        #expect(try await s.trackers().map(\.sortOrder) == [0, 1])
    }

    @Test func doneCounterClearsAndCompleteFillsTheDay() async throws {
        let s = try store()
        var glasses = Tracker(name: "Glasses", icon: "drop")
        glasses.type = .count
        glasses.dailyTarget = 8
        glasses = try await s.save(glasses)
        for _ in 0..<8 { try await s.quick(glasses, on: today) }
        try await s.quick(glasses, on: today) // done: back to 0, not a hidden 9
        #expect(try await s.value(of: glasses.id!, on: today) == 0)
        try await s.quick(glasses, on: today - 1)
        try await s.complete(glasses, on: today - 1) // "Complete yesterday" fills it, not +1
        #expect(try await s.value(of: glasses.id!, on: today - 1) == 8)
    }

    @Test func deletedHabitComesBackWithItsHistory() async throws {
        let s = try store()
        var t = Tracker(name: "Run", icon: "person-simple-run")
        t.reminder = ClockTime(7, 30)
        t.cue = "After coffee"
        t = try await s.save(t)
        try await s.quick(t, on: today - 1)
        try await s.saveNote(Note(trackerId: t.id!, date: today - 1, text: "5 km"))

        let item = try #require(try await s.delete(t))
        #expect(try await s.trackers().isEmpty)
        #expect(try await s.db.read { try Tombstone.fetchCount($0) } == 1)

        let back = try await s.restore(item)
        #expect(back.id == t.id)
        #expect(back.uuid == t.uuid)
        #expect(back.reminder == ClockTime(7, 30))
        #expect(back.cue == "After coffee")
        #expect(try await s.value(of: t.id!, on: today - 1) == 1)
        #expect(try await s.notes(of: t.id!).map(\.text) == ["5 km"])
        #expect(try await s.db.read { try Tombstone.fetchCount($0) } == 0)
        #expect(try await s.trash().isEmpty)
    }

    /// A trash copy written by the Android app (org.json, nulls left out) still restores.
    @Test func androidTrashSnapshotReads() throws {
        let old = #"{"habit":{"name":"Read","icon":"book","color":4281808175,"type":"BOOLEAN","dailyTarget":2,"unit":"","direction":"MORE_IS_BETTER","sortOrder":3,"archived":false,"createdAt":1700000000000,"reminder":27000,"deleted":false},"id":7,"days":[[20374,2]],"notes":[[20374,"good, \"quoted\""]]}"#
        let (t, days, notes) = try Trash.unpack(TrashedHabit(uuid: "u1", name: "Read", deletedAt: 0, data: old))
        #expect(t.id == 7)
        #expect(t.color == 0xFF37352F)
        #expect(t.dailyTarget == 2)
        #expect(t.reminder == ClockTime(7, 30))
        #expect(t.cue == nil)
        #expect(days(9) == [Entry(trackerId: 9, date: Day(epochDay: 20374), value: 2, updatedAt: days(9)[0].updatedAt)])
        #expect(notes(9).first?.text == "good, \"quoted\"")
    }

    @Test func recurringTaskMovesOn_oneOffCompletes() async throws {
        let s = try store()
        var weekly = Task(title: "Water plants")
        weekly.dueDate = today - 3
        weekly.repeat = Repeat.weekly([1, 5]).encode() // today is a Thursday: next is Friday
        weekly = try await s.save(weekly)
        let moved = try await s.complete(weekly, today: today)
        #expect(moved.done == false)
        #expect(moved.dueDate == Day(2026, 10, 16))

        let once = try await s.save(Task(title: "Call mom"))
        #expect(try await s.complete(once, today: today).done)
        #expect(try await s.db.read { try HabitStore.openTasks(in: $0) }.map(\.title) == ["Water plants"])
    }

    /// A backup file written by the Android app opens here, and one we write opens there (same schema).
    @Test func androidBackupFileOpens() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let android = dir.appendingPathComponent("habits-2026-10-15.db")
        // What Room leaves on disk: its tables, its master table and user_version 8, no GRDB bookkeeping.
        let q = try DatabaseQueue(path: android.path)
        try await q.write { db in
            for sql in Schema.statements { try db.execute(sql: sql) }
            try db.execute(sql: "PRAGMA user_version = 8")
            try db.execute(sql: "INSERT INTO tracker (name, icon, color, type, dailyTarget, unit, direction, sortOrder, archived, createdAt, uuid) VALUES ('Read', 'book-open', 0, 'BOOLEAN', 1, '', 'MORE_IS_BETTER', 0, 0, 1, 'abc')")
            try db.execute(sql: "INSERT INTO entry (trackerId, date, value) VALUES (1, \(today.epochDay), 1)")
        }
        #expect(HabitStore.isBackup(android))

        let s = try HabitStore(path: android.path)
        #expect(try await s.trackers().map(\.name) == ["Read"])
        #expect(try await s.db.read { try Int32.fetchOne($0, sql: "PRAGMA user_version") } == 8)

        // Exporting while a live query is open (as in the app) still works.
        let live = _Concurrency.Task { for try await _ in s.observe({ try Tracker.fetchCount($0) }) {} }
        defer { live.cancel() }
        try await _Concurrency.Task.sleep(for: .milliseconds(50))
        let copy = dir.appendingPathComponent("export.db")
        try s.export(to: copy)
        #expect(HabitStore.isBackup(copy))
        #expect(!FileManager.default.fileExists(atPath: copy.path + "-shm"))
        #expect(!HabitStore.isBackup(dir.appendingPathComponent("missing.db")))
    }
}
