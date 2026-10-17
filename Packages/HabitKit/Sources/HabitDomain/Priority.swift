/// Todoist's task priorities: 1 is the most urgent, `none` (4) is none. Same rules as Android's Priority.kt.
public enum Priority {
    public static let none = 4

    /// How dark the flag is drawn: the app is black and white, so urgency is ink depth, not a hue.
    public static func alpha(_ p: Int) -> Double? {
        switch p {
        case 1: 1
        case 2: 0.6
        case 3: 0.35
        default: nil
        }
    }

    /// Quick add like Todoist: "Pay rent p1" saves "Pay rent" at priority 1. The last tag wins.
    public static func parse(_ title: String) -> (title: String, priority: Int?) {
        let words = title.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var priority: Int?
        var rest: [String] = []
        for w in words {
            if w.count == 2, w.first?.lowercased() == "p", let n = Int(String(w.last!)), (1...4).contains(n) { priority = n }
            else { rest.append(w) }
        }
        guard let priority else { return (title, nil) }
        let clean = rest.joined(separator: " ")
        return clean.isEmpty ? (title, nil) : (clean, priority)
    }
}
