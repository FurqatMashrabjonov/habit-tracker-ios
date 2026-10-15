import Foundation
import Testing
import HabitDomain
@testable import HabitData

@Suite struct SyncTests {
    let day = Day(2026, 10, 3)

    @Test func localWritesGoOut_cloudWritesDont() async throws {
        let s = try HabitStore(path: nil)
        let t = try await s.save(Tracker(name: "Read", icon: "book-open"))
        try await s.setValue(1, of: t.id!, on: day)
        try await s.saveNote(Note(trackerId: t.id!, date: day, text: "good"))
        let out = try await s.outbox(since: 0)
        #expect(out.habits.map(\.uuid) == [t.uuid])
        #expect(out.days == [DayRow(habit: t.uuid, date: day, value: 1)])
        #expect(out.months["\(t.uuid)_2026-10"]?.days == ["03": 1])
        #expect(out.months["\(t.uuid)_2026-10"]?.notes == ["03": "good"])

        // A day written from the cloud keeps updatedAt = 0: nothing to send back.
        let later = Clock.nowMillis() + 1
        try await s.applyRemoteMonth(habit: t.uuid, month: "2026-10", days: ["04": 1], notes: [:], start: later)
        #expect(try await s.outbox(since: later - 1).days.isEmpty)
        #expect(try await s.value(of: t.id!, on: day + 1) == 1)
    }

    @Test func deletesLeaveTombstones() async throws {
        let s = try HabitStore(path: nil)
        let t = try await s.save(Tracker(name: "Run", icon: "x"))
        try await s.saveNote(Note(trackerId: t.id!, date: day, text: "x"))
        try await s.deleteNote(of: t.id!, on: day)
        _ = try await s.delete(t)
        let out = try await s.outbox(since: Clock.nowMillis())
        #expect(out.deletedHabits == [t.uuid])
        #expect(out.deletedNotes.map(\.habit) == [t.uuid])
        #expect(out.months["\(t.uuid)_2026-10"]?.notes == ["03": ""])
        try await s.clearTombstones(upTo: Clock.nowMillis())
        #expect(try await s.outbox(since: Clock.nowMillis()).isEmpty)
    }

    @Test func remoteHabitsArriveUpdateAndDelete_butLocalEditsDuringTheRunWin() async throws {
        let s = try HabitStore(path: nil)
        var remote = CloudDoc.tracker(uuid: "u1", ["name": "Walk", "icon": "person-simple-walk", "dailyTarget": 1, "reminder": 27000])
        #expect(try await s.applyRemoteHabit(remote, deleted: false, start: 0))
        #expect(try await s.trackers().map(\.name) == ["Walk"])
        #expect(try await s.applyRemoteHabit(remote, deleted: false, start: 0) == false) // our own push coming back

        // Edited here after the run started: the cloud's older copy doesn't overwrite it.
        let start = Clock.nowMillis()
        var mine = try await s.trackers()[0]
        mine.name = "Long walk"
        try await s.save(mine)
        remote.name = "Walk 2"
        #expect(try await s.applyRemoteHabit(remote, deleted: false, start: start) == false)
        #expect(try await s.trackers()[0].name == "Long walk")

        #expect(try await s.applyRemoteHabit(remote, deleted: true, start: Clock.nowMillis() + 10_000))
        #expect(try await s.trackers().isEmpty)
    }
}
