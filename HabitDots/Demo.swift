import HabitData
import HabitDomain

/// Sample habits with a few months of history, for screenshots and the simulator (`-demo` launch argument).
/// Only fills an empty database.
enum Demo {
    static func seed(_ store: HabitStore, today: Day) async throws {
        guard try await store.trackers(includeArchived: true).isEmpty else { return }
        let habits: [(String, String, String?, Int, Double)] = [
            ("Drink water", "drop", "8 glasses through the day", 8, 0.85),
            ("Read 20 pages", "book-open", "Before bed", 1, 0.7),
            ("Morning run", "person-simple-run", nil, 1, 0.55),
            ("Meditate", "flower-lotus", "10 quiet minutes", 1, 0.8),
        ]
        var seed: UInt64 = 42
        func roll() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
        for (name, icon, cue, target, rate) in habits {
            var t = Tracker(name: name, icon: icon)
            t.cue = cue
            t.dailyTarget = target
            t.createdAt = Int64((today - 180).epochDay) * 86_400_000
            t = try await store.save(t)
            for ago in 1...180 where roll() < rate {
                try await store.setValue(target, of: t.id!, on: today - ago)
            }
        }
    }
}
