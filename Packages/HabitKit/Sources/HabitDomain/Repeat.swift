/// Recurrence rule for a task, stored as a short string in `task.repeat` as on Android:
/// "D", "N3" (every 3 days), "W1,5" (Monday and Friday), "M15" (the 15th).
public enum Repeat: Hashable, Sendable {
    case daily
    case weekly(Set<Int>)
    case monthly(Int)
    case everyDays(Int)

    /// First occurrence strictly after `after`. `everyDays` counts from `after`.
    public func next(after: Day) -> Day {
        switch self {
        case .daily: return after + 1
        case .everyDays(let n): return after + n
        case .weekly(let days):
            var d = after + 1
            while !days.contains(d.weekday) { d = d + 1 }
            return d
        case .monthly(let day):
            let thisMonth = after.withDay(min(day, after.lengthOfMonth))
            if thisMonth > after { return thisMonth }
            let nextMonth = after.addingMonths(1)
            return nextMonth.withDay(min(day, nextMonth.lengthOfMonth))
        }
    }

    public func encode() -> String {
        switch self {
        case .daily: return "D"
        case .everyDays(let n): return "N" + String(n)
        case .weekly(let days): return "W" + days.sorted().map(String.init).joined(separator: ",")
        case .monthly(let d): return "M" + String(d)
        }
    }

    public static func decode(_ s: String?) -> Repeat? {
        guard let s, let first = s.first else { return nil }
        if s == "D" { return .daily }
        let rest = s.dropFirst()
        switch first {
        case "N": return Int(rest).map { .everyDays($0) }
        case "M": return Int(rest).map { .monthly($0) }
        case "W": return .weekly(Set(rest.split(separator: ",").compactMap { Int($0) }))
        default: return nil
        }
    }

    public static let workdays: Set<Int> = [1, 2, 3, 4, 5]
}
