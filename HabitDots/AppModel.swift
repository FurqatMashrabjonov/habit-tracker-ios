import Foundation
import GRDB
import HabitData
import HabitDesign
import HabitDomain
import Observation
import WidgetKit

/// A habit as the home screen shows it: progress per day (value / target), today's count, streak.
struct HabitRow: Identifiable, Equatable, Sendable {
    let tracker: Tracker
    let progress: [Day: Double]
    let todayCount: Int
    let streak: Int
    let mustNotMiss: Bool
    /// Today is a rest day.
    var resting = false
    /// The last 30 days' rate (the ring cards).
    var momentum: Double = 0
    var id: Int64 { tracker.id ?? 0 }
    /// A rest day reads as 0 here; the dot wall reads the raw -1 from `progress` to draw its dash.
    func progress(on day: Day) -> Double { max(progress[day] ?? 0, 0) }
}

/// The app's state, like Android's TodayViewModel: one live query over habits and their days,
/// re-run on any write (also from the widget).
@MainActor
@Observable
final class AppModel {
    private(set) var store: HabitStore
    private(set) var rows: [HabitRow]? = nil { didSet { remindersChanged(); milestone(after: oldValue) } }
    private(set) var today = Day.today
    private(set) var tasks: [Task] = [] { didSet { remindersChanged() } }
    /// A habit to show on top of the home screen (a tapped reminder; later widgets and deep links).
    var openHabit: Int64?
    private var reminderJob: _Concurrency.Task<Void, Never>?
    private var observers: [_Concurrency.Task<Void, Never>] = []

    init(store: HabitStore) { self.store = store }

    nonisolated static var databasePath: String { Shared.databasePath }

    /// The one model, also reached by notification actions.
    static let shared = AppModel(store: try! HabitStore(path: databasePath))

    /// Any change to habits, days or tasks reschedules the reminders, once the burst of writes settles.
    private func remindersChanged() {
        reminderJob?.cancel()
        let store = store, day = today
        reminderJob = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(for: .milliseconds(500))
            guard !_Concurrency.Task.isCancelled else { return }
            await Reminders.rebuild(store, today: day)
            WidgetCenter.shared.reloadAllTimelines()
            Sync.shared.request()
        }
    }

    /// History the cards draw; a year of weeks is more than any phone shows.
    nonisolated static let historyDays = 400

    func start() async {
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            UserDefaults.standard.set(true, forKey: "onboarded")
            try? await Demo.seed(store, today: today)
        }
        observe()
        _Concurrency.Task { try? await Backups.runIfDue(store) }
        // A new day re-runs the queries with the new date (midnight, time zone change).
        for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
            today = .today
            observe()
        }
    }

    /// (Re)starts the live queries for the current database and day. Also on returning to the app:
    /// a widget's check is written by another process, which these queries don't see on their own.
    func observe() {
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
        Sync.shared.reset() // the restored habits go up to the account on the next sync
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
            for e in mine { progress[e.date] = min(Double(e.value) / Double(t.target), 1) } // a rest day stays negative: the dot wall's dash
            let done = Set(mine.filter { t.isDone($0.value) }.map(\.date))
            let rule = t.rule
            let rest = mine.restDays
            let skip: Skip = { rule.skip($0, done: done, today: today, rest: rest) }
            let created = Day.from(millis: t.createdAt)
            return HabitRow(
                tracker: t, progress: progress,
                todayCount: max(mine.first { $0.date == today }?.value ?? 0, 0),
                streak: currentStreak(done, today: today, skip: skip),
                mustNotMiss: mustNotMissToday(done, today: today, since: max(created, from), skip: skip),
                resting: rest.contains(today),
                momentum: momentum(done, today: today, since: min(created, done.min() ?? created), skip: skip)
            )
        }
    }

    func save(_ task: Task) { _Concurrency.Task { try? await store.save(task) } }
    func delete(_ task: Task) { _Concurrency.Task { try? await store.delete(task) } }
    func complete(_ task: Task) {
        let day = today, store = store
        _Concurrency.Task { try? await store.complete(task, today: day) }
        snack = Snack(text: "“\(task.title)” done") { _Concurrency.Task { try? await store.save(task) } }
    }

    /// A short message over the bottom of the home screen with Undo, as on Android.
    struct Snack: Identifiable {
        let id = UUID()
        let text: String
        /// nil: a plain message without the Undo button.
        var undo: (@MainActor () -> Void)?
    }
    var snack: Snack?

    /// Streak lengths worth a word on the home screen.
    private static let milestones: Set<Int> = [7, 30, 50, 100, 200, 365]

    /// A streak reaching a milestone while the app is open: a line at the bottom and a stronger buzz.
    /// Only an increase between two reads counts, so opening the app on day 30 doesn't celebrate again.
    private func milestone(after old: [HabitRow]?) {
        guard let old, let rows else { return }
        let before = Dictionary(old.map { ($0.id, $0.streak) }, uniquingKeysWith: { a, _ in a })
        guard let hit = rows.first(where: { r in (before[r.id]).map { r.streak > $0 } == true && Self.milestones.contains(r.streak) }) else { return }
        Haptics.done()
        snack = Snack(text: "\(hit.streak) days in a row: \(hit.tracker.name). Keep going.")
    }

    /// Deletes with Undo; Settings › Recently deleted keeps it for 30 days after that.
    func delete(_ t: Tracker) {
        let store = store
        _Concurrency.Task {
            guard let item = try? await store.delete(t) else { return }
            snack = Snack(text: "“\(t.name)” deleted") { _Concurrency.Task { try? await store.restore(item) } }
        }
    }

    func archive(_ t: Tracker) {
        var t = t
        t.archived = true
        _Concurrency.Task { [t, store] in _ = try? await store.save(t) }
    }

    /// Blank text removes the note.
    func saveNote(_ text: String, of t: Tracker, on day: Day) {
        guard let id = t.id else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines), store = store
        _Concurrency.Task {
            if trimmed.isEmpty { try? await store.deleteNote(of: id, on: day) }
            else { try? await store.saveNote(Note(trackerId: id, date: day, text: trimmed)) }
        }
    }

    /// A new habit order, top to bottom, after a drag on the home screen.
    func reorder(_ ids: [Int64]) { let store = store; _Concurrency.Task { try? await store.reorder(ids) } }

    func toggleRest(_ t: Tracker, on day: Day? = nil) {
        guard let id = t.id else { return }
        let store = store, day = day ?? today
        _Concurrency.Task { try? await store.toggleRest(id, on: day) }
    }

    func toggle(_ t: Tracker, on day: Day? = nil) {
        _Concurrency.Task { try? await store.quick(t, on: day ?? today) }
    }
}
