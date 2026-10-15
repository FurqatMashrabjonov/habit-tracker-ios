/// A calendar day as days since 1970-01-01, the way the database stores it (Room's `LocalDate.toEpochDay()`).
/// Proleptic Gregorian, no time zone: a day is a day. Conversions use Howard Hinnant's civil-date algorithms.
public struct Day: Hashable, Comparable, Strideable, Sendable, CustomStringConvertible {
    public let epochDay: Int

    public init(epochDay: Int) { self.epochDay = epochDay }

    public init(_ year: Int, _ month: Int, _ day: Int) {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        epochDay = era * 146097 + doe - 719468
    }

    /// (year, month 1...12, day 1...31)
    public var civil: (year: Int, month: Int, day: Int) {
        let z = epochDay + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }

    public var year: Int { civil.year }
    public var month: Int { civil.month }
    public var day: Int { civil.day }

    /// ISO weekday: Monday = 1 ... Sunday = 7 (1970-01-01 was a Thursday).
    public var weekday: Int { ((epochDay + 3) % 7 + 7) % 7 + 1 }

    public var isLeapYear: Bool { let y = year; return y % 4 == 0 && (y % 100 != 0 || y % 400 == 0) }

    public var lengthOfMonth: Int {
        switch month {
        case 2: return isLeapYear ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// The Monday of this day's week.
    public var weekStart: Day { self - (weekday - 1) }

    public func withDay(_ d: Int) -> Day { Day(year, month, d) }

    /// Same day of month `n` months on, clamped to the target month's length (like java.time).
    public func addingMonths(_ n: Int) -> Day {
        let (y, m, d) = civil
        let total = y * 12 + (m - 1) + n
        let ny = total >= 0 ? total / 12 : (total - 11) / 12
        let nm = total - ny * 12 + 1
        let first = Day(ny, nm, 1)
        return Day(ny, nm, min(d, first.lengthOfMonth))
    }

    public static func + (lhs: Day, rhs: Int) -> Day { Day(epochDay: lhs.epochDay + rhs) }
    public static func - (lhs: Day, rhs: Int) -> Day { Day(epochDay: lhs.epochDay - rhs) }
    public static func - (lhs: Day, rhs: Day) -> Int { lhs.epochDay - rhs.epochDay }
    public static func < (lhs: Day, rhs: Day) -> Bool { lhs.epochDay < rhs.epochDay }

    public func distance(to other: Day) -> Int { other.epochDay - epochDay }
    public func advanced(by n: Int) -> Day { self + n }

    /// "2026-10-15", the form notes and sync keys use.
    public var description: String {
        let (y, m, d) = civil
        return String(y) + "-" + (m < 10 ? "0" : "") + String(m) + "-" + (d < 10 ? "0" : "") + String(d)
    }

    /// Parses "yyyy-MM-dd"; nil for anything else.
    public init?(_ iso: String) {
        let parts = iso.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), d >= 1, d <= Day(y, m, 1).lengthOfMonth else { return nil }
        self.init(y, m, d)
    }
}

/// A time of day in seconds since midnight (Room's `LocalTime.toSecondOfDay()`), for reminders.
public struct ClockTime: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let secondOfDay: Int

    public init(secondOfDay: Int) { self.secondOfDay = secondOfDay }
    public init(_ hour: Int, _ minute: Int) { secondOfDay = hour * 3600 + minute * 60 }

    public var hour: Int { secondOfDay / 3600 }
    public var minute: Int { secondOfDay % 3600 / 60 }

    public static func < (lhs: ClockTime, rhs: ClockTime) -> Bool { lhs.secondOfDay < rhs.secondOfDay }

    /// "07:30"
    public var description: String {
        (hour < 10 ? "0" : "") + String(hour) + ":" + (minute < 10 ? "0" : "") + String(minute)
    }
}
