import Foundation
import UserNotifications
import HabitData
import HabitDomain

/*
 * Reminders, as on Android: one a day per habit at its time (skipped on days it's done or off), one per
 * task at its due time, each with Done and +1 hour buttons that work without opening the app.
 *
 * iOS can't decide at fire time whether to show a local notification, so the next few days are
 * scheduled ahead and the whole set is rebuilt whenever habits, days or tasks change. iOS keeps at
 * most 64 pending; the habit days shrink to fit.
 */
enum Reminders {
    static let habitCategory = "habit"
    static let taskCategory = "task"
    static let doneAction = "done"
    static let snoozeAction = "snooze"

    static func registerCategories() {
        let done = UNNotificationAction(identifier: doneAction, title: "Done", options: [])
        let snooze = UNNotificationAction(identifier: snoozeAction, title: "+1 hour", options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: habitCategory, actions: [done, snooze], intentIdentifiers: []),
            UNNotificationCategory(identifier: taskCategory, actions: [done, snooze], intentIdentifiers: []),
        ])
    }

    /// Asks once, when the user first sets a reminder (Android asks at the same moment).
    static func askPermission() {
        _Concurrency.Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) }
    }

    /// Replaces every scheduled habit and task reminder with ones built from the database now.
    static func rebuild(_ store: HabitStore, today: Day) async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus != .denied else { return }
        let plans: [ReminderPlan]
        do { plans = try await store.db.read { try ReminderPlan.all($0, today: today, now: Date(), calendar: .current) } } catch { return }
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("h:") || $0.hasPrefix("t:") }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        for p in plans { try? await center.add(request(p)) }
    }

    private static func request(_ p: ReminderPlan) -> UNNotificationRequest {
        let c = UNMutableNotificationContent()
        c.title = p.title
        c.body = p.body
        c.sound = .default
        c.categoryIdentifier = p.isTask ? taskCategory : habitCategory
        c.userInfo = p.info
        c.interruptionLevel = .timeSensitive
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: p.at)
        return UNNotificationRequest(identifier: p.id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
    }

    /// A one-off reminder an hour from now for the notification the user snoozed.
    static func snooze(_ content: UNNotificationContent, id: String) {
        let c = content.mutableCopy() as! UNMutableNotificationContent
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "s:\(id):\(UUID().uuidString)", content: c, trigger: trigger))
    }

}

import GRDB

/// Notification taps and buttons. Done logs the habit (+1, never an undo: it may have been done
/// elsewhere since) or completes the task; +1 hour shows it again later.
final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable { // no state
    static let shared = NotificationHandler()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        let info = content.userInfo
        switch response.actionIdentifier {
        case Reminders.doneAction:
            await MainActor.run { () -> HabitStore in AppModel.shared.store }.done(info)
        case Reminders.snoozeAction:
            Reminders.snooze(content, id: response.notification.request.identifier)
        case UNNotificationDefaultActionIdentifier:
            if let id = (info["habit"] as? NSNumber)?.int64Value { await MainActor.run { AppModel.shared.openHabit = id } }
        default:
            break
        }
    }
}

private extension HabitStore {
    func done(_ info: [AnyHashable: Any]) async {
        if let id = (info["habit"] as? NSNumber)?.int64Value, let day = (info["day"] as? NSNumber)?.intValue {
            _ = try? await db.write { db in
                guard let t = try Tracker.fetchOne(db, key: id) else { return }
                let date = Day(epochDay: day)
                let v = try Int.fetchOne(db, sql: "SELECT value FROM entry WHERE trackerId = ? AND date = ?", arguments: [id, date]) ?? 0
                if !t.isDone(v) { try HabitStore.quick(in: db, t, id: id, on: date) }
            }
        } else if let id = (info["task"] as? NSNumber)?.int64Value, let task = try? await db.read({ try Task.fetchOne($0, key: id) }), !task.done {
            _ = try? await complete(task, today: .today)
        }
    }
}
