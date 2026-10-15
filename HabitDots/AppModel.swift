import Foundation
import GRDB
import HabitData
import HabitDomain
import Observation

/// A habit as the home screen shows it: progress per day (value / target), today's count, streak.
struct HabitRow: Identifiable, Equatable, Sendable {
    let tracker: Tracker
    let progress: [Day: Double]
    let todayCount: Int
    let streak: Int
    let mustNotMiss: Bool
    var id: Int64 { tracker.id ?? 0 }
    func progress(on day: Day) -> Double { progress[day] ?? 0 }
}

/// The app's state, like Android's TodayViewModel: one live query over habits and their days,
/// re-run on any write (also from the widget).
@MainActor
@Observable
final class AppModel {
    let store: HabitStore
    private(set) var rows: [HabitRow]? = nil
    private(set) var today = Day.today

    init(store: HabitStore) { self.store = store }

    /// The database in the App Group container (shared with the widget), or Application Support
    /// when the group isn't available (simulator builds without signing).
    static func live() -> AppModel {
        let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.app.habitdots")
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = try! HabitStore(path: dir.appendingPathComponent("habit.db").path)
        return AppModel(store: store)
    }

    /// History the cards draw; a year of weeks is more than any phone shows.
    nonisolated static let historyDays = 400

    func start() async {
        if ProcessInfo.processInfo.arguments.contains("-demo") { try? await Demo.seed(store, today: today) }
        // A new day re-runs the query with the new date (midnight, time zone change).
        let days = NotificationCenter.default.notifications(named: .NSCalendarDayChanged)
        _Concurrency.Task { for await _ in days { self.today = .today } }
        while !_Concurrency.Task.isCancelled {
            let day = today
            let observation = store.observe { db in try Self.load(db, today: day) }
            do {
                for try await rows in observation {
                    self.rows = rows
                    if today != day { break }
                }
            } catch { break }
        }
    }

    nonisolated static func load(_ db: Database, today: Day) throws -> [HabitRow] {
        let trackers = try HabitStore.trackers(in: db)
        let from = today - historyDays
        let entries = try Entry.filter(Column("date") >= from).fetchAll(db)
        let byHabit = Dictionary(grouping: entries, by: \.trackerId)
        return trackers.map { t in
            let mine = byHabit[t.id ?? -1] ?? []
            var progress: [Day: Double] = [:]
            for e in mine { progress[e.date] = min(Double(e.value) / Double(t.target), 1) }
            let done = Set(mine.filter { t.isDone($0.value) }.map(\.date))
            let rule = t.rule
            let skip: Skip = { rule.skip($0, done: done, today: today) }
            let created = Day.from(millis: t.createdAt)
            return HabitRow(
                tracker: t, progress: progress,
                todayCount: mine.first { $0.date == today }?.value ?? 0,
                streak: currentStreak(done, today: today, skip: skip),
                mustNotMiss: mustNotMissToday(done, today: today, since: max(created, from), skip: skip)
            )
        }
    }

    func toggle(_ t: Tracker, on day: Day? = nil) {
        _Concurrency.Task { try? await store.quick(t, on: day ?? today) }
    }
}

extension Day {
    /// Today in the phone's calendar and time zone.
    static var today: Day { from(date: Date()) }

    static func from(date: Date) -> Day {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return Day(c.year!, c.month!, c.day!)
    }

    static func from(millis: Int64) -> Day { from(date: Date(timeIntervalSince1970: Double(millis) / 1000)) }
}
