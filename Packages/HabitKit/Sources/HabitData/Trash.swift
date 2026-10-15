import Foundation
import HabitDomain

/*
 * Deleting a habit removes it everywhere (sync carries the delete to every phone), so a mistake would
 * cost its whole history. Every delete keeps a copy in `trash` first, in the same JSON the Android
 * app writes: `{"habit": {...cloud document...}, "id": 7, "days": [[epochDay, value]], "notes": [[epochDay, "text"]]}`.
 */
public enum Trash {
    public static let keepDays = 30

    public static func snapshot(_ t: Tracker, entries: [Entry], notes: [Note]) throws -> String {
        let o: [String: Any] = [
            "habit": CloudDoc.from(t),
            "id": t.id ?? 0,
            "days": entries.map { [$0.date.epochDay, $0.value] },
            "notes": notes.map { [$0.date.epochDay, $0.text] as [Any] },
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]), as: UTF8.self)
    }

    /// The habit under its old local id (ids are never reused, so it's free); its days and notes for
    /// the id it gets once inserted.
    public static func unpack(_ item: TrashedHabit) throws -> (Tracker, (Int64) -> [Entry], (Int64) -> [Note]) {
        guard let o = try JSONSerialization.jsonObject(with: Data(item.data.utf8)) as? [String: Any],
              let h = o["habit"] as? [String: Any] else { throw CocoaError(.coderInvalidValue) }
        var tracker = CloudDoc.tracker(uuid: item.uuid, h)
        tracker.id = (o["id"] as? NSNumber)?.int64Value
        let days = (o["days"] as? [[Any]] ?? []).compactMap { r -> (Day, Int)? in
            guard r.count == 2, let d = r[0] as? NSNumber, let v = r[1] as? NSNumber else { return nil }
            return (Day(epochDay: d.intValue), v.intValue)
        }
        let notes = (o["notes"] as? [[Any]] ?? []).compactMap { r -> (Day, String)? in
            guard r.count == 2, let d = r[0] as? NSNumber, let s = r[1] as? String else { return nil }
            return (Day(epochDay: d.intValue), s)
        }
        return (tracker, { id in days.map { Entry(trackerId: id, date: $0.0, value: $0.1) } },
                { id in notes.map { Note(trackerId: id, date: $0.0, text: $0.1) } })
    }
}

/// A habit as its Firestore document (`users/{uid}/habits/{uuid}`), the shape Android writes.
public enum CloudDoc {
    public static func from(_ t: Tracker) -> [String: Any] {
        [
            "name": t.name, "icon": t.icon, "color": t.color, "type": t.type.rawValue, "dailyTarget": t.dailyTarget, "unit": t.unit,
            "direction": t.direction.rawValue, "sortOrder": t.sortOrder, "archived": t.archived, "createdAt": t.createdAt,
            "cue": t.cue as Any, "identity": t.identity as Any, "reminder": t.reminder.map { $0.secondOfDay } as Any,
            "schedule": t.schedule as Any, "deleted": false,
        ].compactMapValues { $0 is NSNull ? nil : $0 }
    }

    /// A habit from the cloud, marked as not edited locally (`updatedAt = 0`).
    public static func tracker(uuid: String, _ d: [String: Any]) -> Tracker {
        func int(_ k: String) -> Int64? { (d[k] as? NSNumber)?.int64Value }
        var t = Tracker(name: d["name"] as? String ?? "", icon: d["icon"] as? String ?? "")
        t.uuid = uuid
        t.updatedAt = 0
        t.color = int("color") ?? 0xFF37352F
        t.type = TrackerType(rawValue: d["type"] as? String ?? "") ?? .boolean
        t.dailyTarget = Int(int("dailyTarget") ?? 1)
        t.unit = d["unit"] as? String ?? ""
        t.direction = Direction(rawValue: d["direction"] as? String ?? "") ?? .moreIsBetter
        t.sortOrder = Int(int("sortOrder") ?? 0)
        t.archived = (d["archived"] as? Bool) ?? false
        t.createdAt = int("createdAt") ?? 0
        t.cue = d["cue"] as? String
        t.identity = d["identity"] as? String
        t.reminder = int("reminder").map { ClockTime(secondOfDay: Int($0)) }
        t.schedule = d["schedule"] as? String
        return t
    }
}
