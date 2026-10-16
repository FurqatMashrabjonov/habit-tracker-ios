/// How often a habit is due. Stored in `tracker.schedule` as on Android: nil = every day,
/// "W1,3,5" = those weekdays (Monday = 1), "T3" = any three days a week.
public enum Schedule: Hashable, Sendable {
    case daily
    case weekdays(Set<Int>)
    /// Any `times` days of each Monday-to-Sunday week.
    case perWeek(Int)

    public func encode() -> String? {
        switch self {
        case .daily: return nil
        case .weekdays(let days): return "W" + days.sorted().map(String.init).joined(separator: ",")
        case .perWeek(let n): return "T" + String(n)
        }
    }

    public static func decode(_ s: String?) -> Schedule {
        guard let s, let first = s.first else { return .daily }
        let rest = s.dropFirst()
        switch first {
        case "W": return .weekdays(Set(rest.split(separator: ",").compactMap { Int($0) }))
        case "T": return Int(rest).map { .perWeek($0) } ?? .daily
        default: return .daily
        }
    }

    /// Still needs doing on `date`, given the days already `done`.
    public func due(_ date: Day, done: Set<Day>) -> Bool {
        guard !done.contains(date) else { return false }
        switch self {
        case .daily: return true
        case .weekdays(let days): return days.contains(date.weekday)
        case .perWeek(let times): return Self.doneInWeek(of: date, done) < times
        }
    }

    /// A not-done `date` that is neither a miss nor progress: an off day, a week whose quota is met,
    /// the current week while the quota can still be reached, or a `rest` day the user marked (sick,
    /// travelling). Streaks step over it.
    public func skip(_ date: Day, done: Set<Day>, today: Day, rest: Set<Day> = []) -> Bool {
        guard !done.contains(date) else { return false }
        if rest.contains(date) { return true }
        switch self {
        case .daily: return false
        case .weekdays(let days): return !days.contains(date.weekday)
        case .perWeek(let times): return Self.doneInWeek(of: date, done) >= times || date.weekStart == today.weekStart
        }
    }

    private static func doneInWeek(of date: Day, _ done: Set<Day>) -> Int {
        let start = date.weekStart
        return (0..<7).count { done.contains(start + $0) }
    }
}
