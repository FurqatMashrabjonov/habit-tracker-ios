import AppIntents
import WidgetKit
import GRDB
import HabitData
import HabitDomain

// ---- Buttons on the widgets -----------------------------------------------------------------------

/// The check on a habit widget: +1 until done, then back to 0, the same one-tap rule as the app.
struct ToggleHabit: AppIntent {
    static let title: LocalizedStringResource = "Check habit"
    static let isDiscoverable = false
    @Parameter(title: "Habit") var id: Int

    init() {}
    init(id: Int64) { self.id = Int(id) }

    func perform() async throws -> some IntentResult {
        let store = try HabitStore(path: Shared.databasePath)
        let key = Int64(id)
        try await store.db.write { db in
            guard let t = try Tracker.fetchOne(db, key: key) else { return }
            try HabitStore.quick(in: db, t, id: key, on: .today)
        }
        return .result()
    }
}

/// The check on an Inbox row: done, or on to the next date when it repeats.
struct CompleteTask: AppIntent {
    static let title: LocalizedStringResource = "Complete task"
    static let isDiscoverable = false
    @Parameter(title: "Task") var id: Int

    init() {}
    init(id: Int64) { self.id = Int(id) }

    func perform() async throws -> some IntentResult {
        let store = try HabitStore(path: Shared.databasePath)
        let key = Int64(id)
        if let task = try await store.db.read({ try Task.fetchOne($0, key: key) }), !task.done {
            try await store.complete(task, today: .today)
        }
        return .result()
    }
}

// ---- Widget settings (the "Edit Widget" sheet) -------------------------------------------------------

/// A widget's look: what it is made of, never what colour it is (Android's Look).
enum WidgetLook: String, AppEnum {
    case auto, clear, glass, terminal
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Look"
    static let caseDisplayRepresentations: [WidgetLook: DisplayRepresentation] = [
        .auto: "Paper / Night", .clear: "Clear (Pro)", .glass: "Glass (Pro)", .terminal: "Terminal (Pro)",
    ]
}

/// What a single-habit widget leads with. Only the wall is free.
enum HabitLayoutOption: String, AppEnum {
    case wall, week, ring, hero
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Layout"
    static let caseDisplayRepresentations: [HabitLayoutOption: DisplayRepresentation] = [
        .wall: "Dot wall", .week: "Last 7 days (Pro)", .ring: "This month (Pro)", .hero: "Streak (Pro)",
    ]
}

/// Checklist rows: icon, name and streak; name only; or name with the last 7 days.
enum RowStyleOption: String, AppEnum {
    case regular, compact, dots
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Rows"
    static let caseDisplayRepresentations: [RowStyleOption: DisplayRepresentation] = [
        .regular: "Icon, name and streak", .compact: "Name only (Pro)", .dots: "Name and last 7 days (Pro)",
    ]
}

struct HabitEntity: AppEntity {
    let id: String
    let name: String
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Habit"
    static let defaultQuery = HabitQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct HabitQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [HabitEntity] { try await all().filter { identifiers.contains($0.id) } }
    func suggestedEntities() async throws -> [HabitEntity] { try await all() }
    func defaultResult() async -> HabitEntity? { try? await all().first }
    private func all() async throws -> [HabitEntity] {
        let store = try HabitStore(path: Shared.databasePath)
        return try await store.trackers().map { HabitEntity(id: String($0.id ?? 0), name: $0.name) }
    }
}

struct HabitWidgetConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Habit"
    @Parameter(title: "Habit") var habit: HabitEntity?
    @Parameter(title: "Layout", default: .wall) var layout: HabitLayoutOption
    @Parameter(title: "Look", default: .auto) var look: WidgetLook
    @Parameter(title: "Dark text", default: false) var darkText: Bool
}

struct ChecklistConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Checklist"
    @Parameter(title: "Rows", default: .regular) var rows: RowStyleOption
    @Parameter(title: "Look", default: .auto) var look: WidgetLook
    @Parameter(title: "Dark text", default: false) var darkText: Bool
}

struct InboxConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Inbox"
    @Parameter(title: "Look", default: .auto) var look: WidgetLook
    @Parameter(title: "Dark text", default: false) var darkText: Bool
}
