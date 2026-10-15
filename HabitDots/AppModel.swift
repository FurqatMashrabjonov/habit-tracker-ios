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
    private(set) var store: HabitStore
    private(set) var rows: [HabitRow]? = nil
    private(set) var today = Day.today
    private(set) var tasks: [Task] = []
    private var observers: [_Concurrency.Task<Void, Never>] = []

    init(store: HabitStore) { self.store = store }

    /// The App Group container (shared with the widget), or Application Support when the group isn't
    /// available (simulator builds without signing).
    nonisolated static var dataDirectory: URL {
        let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.app.habitdots")
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    nonisolated static var databasePath: String { dataDirectory.appendingPathComponent("habit.db").path }

    static func live() -> AppModel { AppModel(store: try! HabitStore(path: databasePath)) }

    /// History the cards draw; a year of weeks is more than any phone shows.
    nonisolated static let historyDays = 400

    func start() async {
        if ProcessInfo.processInfo.arguments.contains("-demo") { try? await Demo.seed(store, today: today) }
        observe()
        _Concurrency.Task { try? await Backups.runIfDue(store) }
        // A new day re-runs the queries with the new date (midnight, time zone change).
        for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
            today = .today
            observe()
        }
    }

    /// (Re)starts the live queries for the current database and day.
    private func observe() {
        observers.forEach { $0.cancel() }
        let store = store, day = today
        observers = [
            _Concurrency.Task { [weak self] in
                do { for try await rows in store.observe({ try Self.load($0, today: day) }) { self?.rows = rows } } catch {}
            },
            _Concurrency.Task { [weak self] in
                do { for try await t in store.observe({ try HabitStore.openTasks(in: $0) }) { self?.tasks = t } } catch {}
            },
        ]
    }

    /// Replaces every habit, day and note with a backup file (from this app or the Android one).
    /// The current data is saved to the automatic backups first, so a wrong pick can be undone.
    func restore(from url: URL) throws {
        guard HabitStore.isBackup(url) else { throw CocoaError(.fileReadCorruptFile) }
        try? Backups.save(store, kind: "before-restore")
        observers.forEach { $0.cancel() }
        try store.db.close()
        let path = Self.databasePath
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }
        try FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: path))
        store = try HabitStore(path: path)
        observe()
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

    func save(_ task: Task) { _Concurrency.Task { try? await store.save(task) } }
    func delete(_ task: Task) { _Concurrency.Task { try? await store.delete(task) } }
    func complete(_ task: Task) { let day = today; _Concurrency.Task { try? await store.complete(task, today: day) } }

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
