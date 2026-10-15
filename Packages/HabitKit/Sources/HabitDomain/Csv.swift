/// Spreadsheet export: one row per habit per day that was done or has a note. Same file as Android's.
public enum Csv {
    public struct Habit: Sendable { public let id: Int64; public let name: String; public let target: Int
        public init(id: Int64, name: String, target: Int) { self.id = id; self.name = name; self.target = target } }
    public struct Entry: Sendable { public let habitId: Int64; public let date: Day; public let value: Int
        public init(habitId: Int64, date: Day, value: Int) { self.habitId = habitId; self.date = date; self.value = value } }
    public struct Note: Sendable { public let habitId: Int64; public let date: Day; public let text: String
        public init(habitId: Int64, date: Day, text: String) { self.habitId = habitId; self.date = date; self.text = text } }

    /// `habits` in list order; rows come out by date, then by that order.
    public static func build(habits: [Habit], entries: [Entry], notes: [Note]) -> String {
        struct Key: Hashable { let habit: Int64; let date: Day }
        let names = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0.name) })
        let targets = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, max($0.target, 1)) })
        let order = Dictionary(uniqueKeysWithValues: habits.enumerated().map { ($1.id, $0) })
        let done = Set(entries.filter { $0.value >= (targets[$0.habitId] ?? 1) }.map { Key(habit: $0.habitId, date: $0.date) })
        let noteText = Dictionary(notes.map { (Key(habit: $0.habitId, date: $0.date), $0.text) }, uniquingKeysWith: { a, _ in a })
        let keys = Set(done).union(noteText.keys).filter { names[$0.habit] != nil }
            .sorted { ($0.date, order[$0.habit] ?? 0) < ($1.date, order[$1.habit] ?? 0) }
        var out = "date,habit,done,note\r\n"
        for k in keys {
            out += k.date.description + "," + field(names[k.habit] ?? "") + "," + (done.contains(k) ? "1" : "0") + "," + field(noteText[k] ?? "") + "\r\n"
        }
        return out
    }

    /// RFC 4180: quote when needed, double inner quotes.
    static func field(_ s: String) -> String {
        s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
            ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }
}

private extension String {
    func replacingOccurrences(of target: String, with replacement: String) -> String {
        split(separator: target, omittingEmptySubsequences: false).joined(separator: replacement)
    }
}
