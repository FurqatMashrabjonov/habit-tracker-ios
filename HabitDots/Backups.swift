import Foundation
import HabitData
import HabitDomain

/// Backups the user can see: weekly copies in the app's Documents folder (Files › On My iPhone ›
/// HabitDots), the newest five kept. They are plain HabitDots databases, the same files the Android
/// app writes, so one can go to an Android phone and back.
enum Backups {
    static let keep = 5
    static let everyDays = 7
    private static let prefix = "HabitDots-"

    static var folder: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    struct Copy: Identifiable, Hashable { let url: URL; let modified: Date; var id: URL { url } }

    /// A dated file name, like Android's `habits-2026-10-15.db`.
    static func fileName(_ kind: String = "habits") -> String { "\(kind)-\(Day.today).db" }

    static func runIfDue(_ store: HabitStore) async throws {
        let last = UserDefaults.standard.integer(forKey: "autoBackupDay")
        let today = Day.today.epochDay
        // A last copy "in the future" (the clock was set ahead, then back) would stop copies until that day.
        guard today - last >= everyDays || last > today, try await !store.trackers(includeArchived: true).isEmpty else { return }
        try save(store, kind: "auto")
        UserDefaults.standard.set(today, forKey: "autoBackupDay")
    }

    @discardableResult
    static func save(_ store: HabitStore, kind: String) throws -> URL {
        let url = folder.appendingPathComponent(prefix + fileName(kind))
        try store.export(to: url)
        for old in list().dropFirst(keep) { try? FileManager.default.removeItem(at: old.url) }
        return url
    }

    /// Newest first.
    static func list() -> [Copy] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls.filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "db" }
            .map { Copy(url: $0, modified: (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            .sorted { $0.modified > $1.modified }
    }

    /// A temporary copy of the whole database, for the share sheet / file exporter.
    static func exportCopy(_ store: HabitStore) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName())
        try store.export(to: url)
        return url
    }

    /// The CSV export, as a temporary file.
    static func csv(_ store: HabitStore) async throws -> URL {
        let text = try await store.db.read { db in
            let trackers = try Tracker.fetchAll(db, sql: "SELECT * FROM tracker ORDER BY archived, sortOrder, id")
            let entries = try Entry.fetchAll(db)
            let notes = try Note.fetchAll(db)
            return Csv.build(
                habits: trackers.map { .init(id: $0.id ?? 0, name: $0.name, target: $0.target) },
                entries: entries.map { .init(habitId: $0.trackerId, date: $0.date, value: $0.value) },
                notes: notes.map { .init(habitId: $0.trackerId, date: $0.date, text: $0.text) }
            )
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("habitdots-\(Day.today).csv")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
