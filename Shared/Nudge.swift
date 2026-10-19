import Foundation
import UserNotifications
import GRDB
import HabitData
import HabitDomain

/// Pro's evening check-in: one notification at its time, only on days some habit is still open.
/// Built into the app and the widget: its settings live in the shared defaults, so a check from a
/// widget can redo tonight's.
enum Nudge {
    static let days = 3
    static var enabled: Bool { Shared.defaults.bool(forKey: "nudge") }
    static var time: ClockTime {
        ClockTime(secondOfDay: Shared.defaults.object(forKey: "nudgeAt") as? Int ?? 21 * 3600)
    }

    static func plans(_ db: Database, today: Day, now: Date) throws -> [ReminderPlan] {
        try ReminderPlan.nudges(db, today: today, at: time, now: now, calendar: .current, days: days)
    }

    static func request(_ p: ReminderPlan) -> UNNotificationRequest {
        let c = UNMutableNotificationContent()
        c.title = p.title
        c.body = p.body
        c.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: p.at)
        return UNNotificationRequest(identifier: p.id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
    }

    /// After a check outside the app: tonight's check-in is rewritten, or dropped once nothing is open.
    /// Only one the app already scheduled is touched, so this stays quiet without Pro.
    static func refreshToday(_ store: HabitStore) async {
        let center = UNUserNotificationCenter.current()
        let id = "n:\(Day.today.epochDay)"
        guard await center.pendingNotificationRequests().contains(where: { $0.identifier == id }) else { return }
        center.removePendingNotificationRequests(withIdentifiers: [id])
        let tonight = try? await store.db.read { try plans($0, today: .today, now: Date()) }.first { $0.id == id }
        if let tonight { try? await center.add(request(tonight)) }
    }
}
