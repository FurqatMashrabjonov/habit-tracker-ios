import Foundation
import GRDB
import HabitData
import HabitDomain
import Observation

/// One habit's page, like Android's DetailViewModel: the habit, its days, notes and streaks, live.
struct DetailState: Equatable, Sendable {
    let tracker: Tracker
    let today: Day
    let values: [Day: Int]
    let progress: [Day: Double]
    let done: Set<Day>
    let rest: Set<Day>
    let currentStreak: Int
    let bestStreak: Int
    let notes: [Note]

    func value(on d: Day) -> Int { max(values[d] ?? 0, 0) }
    func isDone(_ d: Day) -> Bool { done.contains(d) }
    func note(on d: Day) -> String? { notes.first { $0.date == d }?.text }
}

@MainActor
@Observable
final class DetailModel {
    let id: Int64
    private let store: HabitStore
    private(set) var state: DetailState?

    init(id: Int64, store: HabitStore) { self.id = id; self.store = store }

    func start(today: Day) async {
        let id = id
        let observation = store.observe { db -> DetailState? in
            guard let t = try Tracker.fetchOne(db, key: id) else { return nil }
            let entries = try Entry.filter(Column("trackerId") == id).fetchAll(db)
            let notes = try Note.filter(Column("trackerId") == id).order(Column("date").desc).fetchAll(db)
            let values = Dictionary(entries.map { ($0.date, $0.value) }, uniquingKeysWith: { a, _ in a })
            let progress = values.mapValues { min(Double($0) / Double(t.target), 1) }
            let done = Set(values.filter { t.isDone($0.value) }.keys)
            let rule = t.rule
            let rest = entries.restDays
            let skip: Skip = { rule.skip($0, done: done, today: today, rest: rest) }
            return DetailState(tracker: t, today: today, values: values, progress: progress, done: done, rest: rest,
                               currentStreak: currentStreak(done, today: today, skip: skip),
                               bestStreak: bestStreak(done, skip: skip), notes: notes)
        }
        do { for try await s in observation { state = s } } catch {}
    }

    func toggle(on day: Day) {
        guard let t = state?.tracker else { return }
        _Concurrency.Task { try? await store.quick(t, on: day) }
    }

    func toggleRest(on day: Day) {
        let store = store, id = id
        _Concurrency.Task { try? await store.toggleRest(id, on: day) }
    }

    /// Blank text deletes the note.
    func saveNote(_ text: String, on day: Day) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        _Concurrency.Task {
            if trimmed.isEmpty { try? await store.deleteNote(of: id, on: day) }
            else { try? await store.saveNote(Note(trackerId: id, date: day, text: trimmed)) }
        }
    }

    func archive() {
        guard var t = state?.tracker else { return }
        t.archived = true
        _Concurrency.Task { [t] in try? await store.save(t) }
    }
}
