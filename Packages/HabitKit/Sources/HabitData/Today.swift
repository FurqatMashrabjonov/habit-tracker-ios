import Foundation
import HabitDomain

public extension Day {
    /// Today in the phone's calendar and time zone.
    static var today: Day { from(date: Date()) }

    static func from(date: Date) -> Day {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return Day(c.year!, c.month!, c.day!)
    }

    static func from(millis: Int64) -> Day { from(date: Date(timeIntervalSince1970: Double(millis) / 1000)) }

    /// Midnight starting this day, in the phone's time zone.
    var start: Date { Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? Date() }
}
