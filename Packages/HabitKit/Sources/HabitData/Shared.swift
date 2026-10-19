import Foundation

/// What the app and its widgets share: the database file and a few flags, in the App Group container.
public enum Shared {
    public static let appGroup = "group.app.habitdots"

    /// The App Group container, or Application Support where the group isn't available (unsigned
    /// simulator builds; the widget then can't see the app's data).
    public static var directory: URL {
        let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? simulatorShared
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Simulator builds without a team lose the App Group entitlement; every app on one simulated
    /// device can still reach this folder, so the app and its widget share the database there.
    private static var simulatorShared: URL? {
        #if targetEnvironment(simulator)
        ProcessInfo.processInfo.environment["SIMULATOR_SHARED_RESOURCES_DIRECTORY"].map {
            URL(fileURLWithPath: $0).appendingPathComponent("HabitDots", isDirectory: true)
        }
        #else
        nil
        #endif
    }

    public static var databasePath: String { directory.appendingPathComponent("habit.db").path }

    /// Settings the widgets read: the app's theme for widgets.
    public static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }
    /// Pro, for the widgets' looks. A file, not defaults: defaults don't cross processes when the group is missing (simulator).
    public static var pro: Bool {
        get { FileManager.default.fileExists(atPath: directory.appendingPathComponent("pro").path) }
        set {
            let url = directory.appendingPathComponent("pro")
            if newValue { FileManager.default.createFile(atPath: url.path, contents: Data()) } else { try? FileManager.default.removeItem(at: url) }
        }
    }
}
