import HabitDomain

/// Names the app shows for dates and schedules. ponytail: English only, like the Android app.
public enum Words {
    public static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    public static let weekdaysShort = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    public static let weekdaysLong = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    /// "October 15"
    public static func date(_ d: Day) -> String { "\(months[d.month - 1]) \(d.day)" }

    /// "Today", "Yesterday" or "Tuesday, October 14".
    public static func longDate(_ d: Day, today: Day) -> String {
        if d == today { return "Today" }
        if d == today - 1 { return "Yesterday" }
        return "\(weekdaysLong[d.weekday - 1]), \(date(d))"
    }

    /// nil for every day; "Mo, We, Fr"; "3 times a week".
    public static func schedule(_ s: Schedule) -> String? {
        switch s {
        case .daily: return nil
        case .weekdays(let days): return days.sorted().map { weekdaysShort[$0 - 1] }.joined(separator: ", ")
        case .perWeek(let n): return "\(n) times a week"
        }
    }
}

public extension Words {
    /// "Today", "Tomorrow" or "October 18".
    static func due(_ d: Day, today: Day) -> String {
        if d == today { return "Today" }
        if d == today + 1 { return "Tomorrow" }
        return date(d)
    }

    static func `repeat`(_ r: Repeat) -> String {
        switch r {
        case .daily: return "Every day"
        case .everyDays(let n): return "Every \(n) days"
        case .monthly(let d): return "Monthly on the \(d)"
        case .weekly(let days):
            if days == Repeat.workdays { return "Weekdays" }
            return "Weekly: " + days.sorted().map { weekdaysShort[$0 - 1] }.joined(separator: ", ")
        }
    }
}
