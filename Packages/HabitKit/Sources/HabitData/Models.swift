import Foundation
import GRDB
import HabitDomain

/*
 * Rows exactly as the Android app stores them (Room schema version 8): same tables, columns and
 * encodings. A backup made on one phone restores on the other.
 */

public enum TrackerType: String, Codable, Sendable { case boolean = "BOOLEAN", count = "COUNT", duration = "DURATION" }
public enum Direction: String, Codable, Sendable { case moreIsBetter = "MORE_IS_BETTER", lessIsBetter = "LESS_IS_BETTER" }

/// Longest habit name: fits one line on a card, a widget row and the share image.
public let nameMax = 40
/// Longest description, task title and note.
public let textMax = 200
public let noteMax = 500

/// A habit.
public struct Tracker: Codable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "tracker"

    public var id: Int64?
    public var name: String
    public var icon: String
    /// ARGB, unused since the app went black and white; kept for the schema.
    public var color: Int64 = 0xFF37352F
    public var type: TrackerType = .boolean
    public var dailyTarget: Int = 1
    public var unit: String = ""
    public var direction: Direction = .moreIsBetter
    public var sortOrder: Int = 0
    public var archived: Bool = false
    public var createdAt: Int64 = Clock.nowMillis()
    /// Implementation intention, e.g. "After morning prayer".
    public var cue: String?
    /// Identity statement, e.g. "I am a healthy person".
    public var identity: String?
    /// Daily reminder; skipped on days the habit is already done.
    public var reminder: ClockTime?
    /// `Schedule.encode()`; nil = every day.
    public var schedule: String?
    /// Id across devices (the local `id` differs per phone).
    public var uuid: String = UUID().uuidString.lowercased()
    /// Last local edit, for sync; 0 = as it came from the cloud. Set by `HabitStore`.
    public var updatedAt: Int64 = Clock.nowMillis()

    public init(name: String, icon: String) { self.name = name; self.icon = icon }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    /// Times a day the habit is done; most habits are once.
    public var target: Int { max(dailyTarget, 1) }
    public func isDone(_ value: Int) -> Bool { value >= target }
    public var rule: Schedule { Schedule.decode(schedule) }
}

/// One row per habit per day: times done that day, or `Entry.rest` for a day off the user marked.
public struct Entry: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "entry"
    /// A rest day (sick, travelling): not done and not missed; streaks step over it. Syncs as -1.
    public static let rest = -1
    public var trackerId: Int64
    public var date: Day
    public var value: Int
    public var updatedAt: Int64 = Clock.nowMillis()
    public init(trackerId: Int64, date: Day, value: Int, updatedAt: Int64 = Clock.nowMillis()) {
        self.trackerId = trackerId; self.date = date; self.value = value; self.updatedAt = updatedAt
    }
}

/// A short journal line for one habit on one day.
public struct Note: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "note"
    public var trackerId: Int64
    public var date: Day
    public var text: String
    public var updatedAt: Int64 = Clock.nowMillis()
    public init(trackerId: Int64, date: Day, text: String, updatedAt: Int64 = Clock.nowMillis()) {
        self.trackerId = trackerId; self.date = date; self.text = text; self.updatedAt = updatedAt
    }
}

/// One-off or recurring task. A recurring task is never marked done: completing it moves `dueDate` on.
public struct Task: Codable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "task"
    public var id: Int64?
    public var title: String
    public var dueDate: Day?
    /// Reminder fires at this time on `dueDate`.
    public var dueTime: ClockTime?
    /// `Repeat.encode()` or nil for one-off.
    public var `repeat`: String?
    /// Todoist scale: 1 = highest, 4 = none.
    public var priority: Int = 4
    public var done: Bool = false
    public var completedAt: Int64?
    public var createdAt: Int64 = Clock.nowMillis()
    public init(title: String) { self.title = title }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    /// Due before `today`, or today at a time already gone.
    public func overdue(today: Day, now: ClockTime) -> Bool {
        guard let day = dueDate else { return false }
        return day < today || (day == today && dueTime.map { $0 < now } == true)
    }
}

/// A local delete still to reach the cloud: "h:<habit uuid>" or "n:<habit uuid>:<date>".
public struct Tombstone: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "tombstone"
    public var key: String
    public var deletedAt: Int64 = Clock.nowMillis()
    public init(key: String) { self.key = key }
}

/// A deleted habit with its days and notes, restorable for `Trash.keepDays`.
public struct TrashedHabit: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "trash"
    public var uuid: String
    public var name: String
    public var deletedAt: Int64
    /// The habit, its days and notes as JSON, see `Trash.snapshot`.
    public var data: String
}

// --- Column encodings shared with Room -------------------------------------------------------

extension Day: DatabaseValueConvertible {
    public var databaseValue: DatabaseValue { Int64(epochDay).databaseValue }
    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> Day? { Int64.fromDatabaseValue(dbValue).map { Day(epochDay: Int($0)) } }
}
extension Day: Codable {
    public init(from decoder: Decoder) throws { self.init(epochDay: Int(try decoder.singleValueContainer().decode(Int64.self))) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(Int64(epochDay)) }
}
extension ClockTime: DatabaseValueConvertible {
    public var databaseValue: DatabaseValue { Int64(secondOfDay).databaseValue }
    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> ClockTime? { Int64.fromDatabaseValue(dbValue).map { ClockTime(secondOfDay: Int($0)) } }
}
extension ClockTime: Codable {
    public init(from decoder: Decoder) throws { self.init(secondOfDay: Int(try decoder.singleValueContainer().decode(Int64.self))) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(Int64(secondOfDay)) }
}

/// Epoch milliseconds, as Android's `System.currentTimeMillis()`; overridable in tests.
public enum Clock {
    nonisolated(unsafe) public static var now: @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
    public static func nowMillis() -> Int64 { now() }
}

public extension Array where Element == Entry {
    var restDays: Set<Day> { Set(filter { $0.value == Entry.rest }.map(\.date)) }
}
