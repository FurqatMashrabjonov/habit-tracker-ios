import SwiftUI
import WidgetKit
import AppIntents
import HabitData
import HabitDesign
import HabitDomain


// ---- Looks ----------------------------------------------------------------------------------------

/// Everything a widget draws with, resolved for one widget (Android's Palette).
struct WidgetPalette {
    let background: Color
    let text: Color
    let dim: Color
    let tile: Color
    /// The tick inside a done check: whatever reads on a solid `text` fill.
    let tick: Color
    let mono: Bool
    let dots: DotShape
    var ink: DotInk = .plain
    /// A bundled font's PostScript name (Dot matrix, Receipt); nil for Inter or the system monospace.
    var fontName: String? = nil
    /// The card: a thin ink border (Outline); a header line and sharp corners (Receipt).
    var outlineCard = false
    var receipt = false

    /// Without Pro every widget falls back to the free look; its settings are kept.
    static func resolve(_ look: WidgetLook, darkText: Bool, scheme: ColorScheme, ignoringPro: Bool = false) -> WidgetPalette {
        let look = look.pro && !Shared.pro && !ignoringPro ? .auto : look
        switch look {
        case .auto:
            let dark = scheme == .dark
            let p = dark ? Ink.dark : Ink.light
            return WidgetPalette(background: p.background, text: p.ink, dim: p.dim, tile: p.tile, tick: p.background, mono: false, dots: .square)
        case .clear, .glass:
            // iOS doesn't tell a widget its wallpaper's tone; dark text is the widget's own setting.
            let text = darkText ? Color(hex: 0x1F1E1B) : Color(hex: 0xF2F2F0)
            let dim = darkText ? Color(hex: 0x4E4C48) : Color(hex: 0xC9C8C4)
            let bg: Color = look == .clear ? .clear : (darkText ? .white.opacity(0.5) : .black.opacity(0.5))
            let tile = darkText ? Color.black.opacity(0.07) : Color.white.opacity(0.14)
            return WidgetPalette(background: bg, text: text, dim: dim, tile: tile, tick: darkText ? .white : .black, mono: false, dots: .square)
        case .terminal:
            return WidgetPalette(background: .black, text: Color(hex: 0xD4D4D2), dim: Color(hex: 0x7A7A78), tile: Color(hex: 0x1C1C1C),
                                 tick: .black, mono: true, dots: .pixel)
        case .dotMatrix:
            return WidgetPalette(background: .black, text: .white, dim: Color(hex: 0x8C8C8C), tile: Color(hex: 0x161617),
                                 tick: .black, mono: false, dots: .round, ink: DotInk(glow: true), fontName: "DotGothic16-Regular")
        case .eink:
            return WidgetPalette(background: Color(hex: 0xECECEA), text: Color(hex: 0x2B2B2B), dim: Color(hex: 0x6E6E6E), tile: Color(hex: 0xDEDEDA),
                                 tick: Color(hex: 0xECECEA), mono: true, dots: .square)
        case .outline:
            return WidgetPalette(background: .white, text: Color(hex: 0x1F1E1B), dim: Color(hex: 0x6B6962), tile: Color(hex: 0xF0F0EC),
                                 tick: .white, mono: false, dots: .round, ink: DotInk(outline: true), outlineCard: true)
        case .receipt:
            return WidgetPalette(background: Color(hex: 0xF4F4F2), text: Color(hex: 0x262626), dim: Color(hex: 0x7B7B78), tile: Color(hex: 0xE6E6E2),
                                 tick: Color(hex: 0xF4F4F2), mono: false, dots: .pixel, fontName: "VT323-Regular", receipt: true)
        }
    }

    func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        // Bundled display faces have one weight and sit smaller on the line, so they get a little more size.
        if let fontName { return .custom(fontName, size: fontName == "VT323-Regular" ? size * 1.25 : size * 1.05) }
        return mono ? .system(size: size, weight: weight, design: .monospaced) : Type.inter(size, weight)
    }
}

private extension View {
    func widgetLook(_ p: WidgetPalette) -> some View {
        foregroundStyle(p.text)
            // Outline: a 1pt ink border that follows the system's own widget shape.
            .containerBackground(for: .widget) {
                ZStack { p.background; if p.outlineCard { ContainerRelativeShape().strokeBorder(p.text, lineWidth: 1) } }
            }
    }
}

/// The Receipt look's dashed total line under a list; nothing for other looks.
private struct LookFooter: View {
    let p: WidgetPalette
    let text: String
    var body: some View {
        if p.receipt { Text("- - - - - - - - - - - - - - - -  \(text)").font(p.font(9)).foregroundStyle(p.dim).lineLimit(1) }
    }
}

private struct IconTile: View {
    let icon: String
    let size: CGFloat
    let p: WidgetPalette
    var body: some View {
        Image("Icons/\(icon)").resizable().frame(width: size * 0.58, height: size * 0.58)
            .frame(width: size, height: size)
            .background(p.tile, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

private struct Streak: View {
    let days: Int
    let p: WidgetPalette
    var size: CGFloat = 11
    var body: some View {
        HStack(spacing: 3) {
            Image("Icons/ui-fire-fill").resizable().frame(width: size + 1, height: size + 1)
            Text("\(days)").font(p.font(size))
        }
        .foregroundStyle(p.dim)
    }
}

private func untilMidnight<E: TimelineEntry>(_ entry: E) -> Timeline<E> {
    // Again at midnight, for the new day's empty box.
    Timeline(entries: [entry], policy: .after(Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400 + 1)))
}

// ---- One habit ------------------------------------------------------------------------------------

struct HabitEntry: TimelineEntry {
    let date: Date
    let today: Day
    let habit: HabitSnap?
    let config: HabitWidgetConfig
}

struct HabitProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HabitEntry {
        HabitEntry(date: Date(), today: .today, habit: Snapshot.sample(today: .today)[0], config: HabitWidgetConfig())
    }
    func snapshot(for config: HabitWidgetConfig, in context: Context) async -> HabitEntry {
        context.isPreview ? placeholder(in: context) : await entry(config)
    }
    func timeline(for config: HabitWidgetConfig, in context: Context) async -> Timeline<HabitEntry> { untilMidnight(await entry(config)) }

    private func entry(_ config: HabitWidgetConfig) async -> HabitEntry {
        let today = Day.today
        var snap: HabitSnap?
        if let store = Snapshot.store() {
            snap = try? await store.db.read { db in
                if let id = config.habit.flatMap({ Int64($0.id) }) { return try Snapshot.habit(db, id: id, today: today) }
                return try Snapshot.habits(db, today: today).first
            }
        }
        return HabitEntry(date: Date(), today: today, habit: snap, config: config)
    }
}

struct HabitWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "habit", intent: HabitWidgetConfig.self, provider: HabitProvider()) { HabitWidgetView(entry: $0) }
            .configurationDisplayName("Habit")
            .description("One habit: quick check and history.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct HabitWidgetView: View {
    let entry: HabitEntry
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetFamily) private var widgetFamily
    /// Set by the debug gallery, which isn't a real widget.
    var size: WidgetFamily? = nil
    private var family: WidgetFamily { size ?? widgetFamily }

    var body: some View {
        let p = WidgetPalette.resolve(entry.config.effectiveLook, darkText: entry.config.darkText, scheme: scheme)
        Group {
            if let h = entry.habit { content(h, p) } else {
                Text("Add a habit in the app").font(p.font(12)).foregroundStyle(p.dim).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .widgetLook(p)
        .widgetURL(entry.habit.map { URL(string: "habitdots://habit/\($0.id)")! })
    }

    @ViewBuilder
    private func content(_ h: HabitSnap, _ p: WidgetPalette) -> some View {
        let layout = entry.config.layout
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                if family != .systemSmall { IconTile(icon: h.icon, size: 30, p: p) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(h.name).font(p.font(family == .systemSmall ? 12 : 14, .bold)).lineLimit(family == .systemSmall ? 2 : 1)
                    if family != .systemSmall || layout != .hero {
                        HStack(spacing: 0) {
                            if h.off { Text("Day off").font(p.font(11)).foregroundStyle(p.dim) } else { Streak(days: h.streak, p: p) }
                            if h.target > 1 { Text("  ·  \(min(h.value, h.target))/\(h.target)").font(p.font(11)).foregroundStyle(p.dim) }
                        }
                    }
                }
                Spacer(minLength: 0)
                Button(intent: ToggleHabit(id: h.id)) {
                    WidgetCheck(done: h.done, partial: h.partial, tick: p.tick).frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }
            switch layout {
            case .wall:
                WidgetDots(data: h.progress, today: entry.today, shape: p.dots, ink: p.ink, off: { h.offDays.contains($0) })
            case .week:
                Spacer(minLength: 0)
                WidgetWeek(data: h.progress, today: entry.today, shape: p.dots, ink: p.ink).frame(maxHeight: 40)
            case .ring:
                // This month: share of due days done, as a ring and a number.
                let rate = h.monthDue == 0 ? 0 : Double(h.monthDone) / Double(h.monthDue)
                HStack(spacing: 14) {
                    ZStack {
                        Circle().stroke(.primary.opacity(0.18), lineWidth: 5)
                        Circle().trim(from: 0, to: rate).stroke(.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                    }
                    .frame(width: 52, height: 52)
                    VStack(alignment: .leading) {
                        Text("\(Int(rate * 100))%").font(p.font(26, .bold))
                        Text("\(h.monthDone) of \(h.monthDue) days").font(p.font(11)).foregroundStyle(p.dim)
                    }
                }
                .frame(maxHeight: .infinity)
            case .hero:
                // The streak as the headline, big; the last 14 days as one row under it.
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(h.streak)").font(p.font(family == .systemSmall ? 36 : 44, .bold))
                    Text("day streak").font(p.font(12)).foregroundStyle(p.dim)
                }
                Spacer(minLength: 0)
                WidgetWeek(data: h.progress, today: entry.today, shape: p.dots, ink: p.ink, days: 14).frame(maxHeight: 14)
            case .bars:
                // One bar per week: how many of its days were done. No dots at all.
                WidgetBars(data: h.progress, today: entry.today, weeks: family == .systemSmall ? 8 : 16)
            }
        }
    }
}

// ---- Checklist ------------------------------------------------------------------------------------

struct ChecklistEntry: TimelineEntry {
    let date: Date
    let today: Day
    let habits: [HabitSnap]
    let config: ChecklistConfig
}

struct ChecklistProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ChecklistEntry {
        ChecklistEntry(date: Date(), today: .today, habits: Snapshot.sample(today: .today), config: ChecklistConfig())
    }
    func snapshot(for config: ChecklistConfig, in context: Context) async -> ChecklistEntry {
        context.isPreview ? placeholder(in: context) : await entry(config)
    }
    func timeline(for config: ChecklistConfig, in context: Context) async -> Timeline<ChecklistEntry> { untilMidnight(await entry(config)) }
    private func entry(_ config: ChecklistConfig) async -> ChecklistEntry {
        let today = Day.today
        let habits = (try? await Snapshot.store()?.db.read { try Snapshot.habits($0, today: today) }) ?? []
        return ChecklistEntry(date: Date(), today: today, habits: habits ?? [], config: config)
    }
}

struct ChecklistWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "checklist", intent: ChecklistConfig.self, provider: ChecklistProvider()) { ChecklistView(entry: $0) }
            .configurationDisplayName("Habit checklist")
            .description("Today's habits, checked from the home screen.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ChecklistView: View {
    let entry: ChecklistEntry
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetFamily) private var widgetFamily
    /// Set by the debug gallery, which isn't a real widget.
    var size: WidgetFamily? = nil
    private var family: WidgetFamily { size ?? widgetFamily }

    var body: some View {
        let p = WidgetPalette.resolve(entry.config.effectiveLook, darkText: entry.config.darkText, scheme: scheme)
        let rows = entry.config.rows
        let counted = entry.habits.filter { !$0.off || $0.done }
        let limit = family == .systemLarge ? (p.receipt ? 7 : 8) : (p.receipt ? 2 : 3)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today").font(p.font(15, .bold))
                Spacer()
                Text("\(counted.filter(\.done).count)/\(counted.count)").font(p.font(13, .bold)).foregroundStyle(p.dim)
            }
            if entry.habits.isEmpty {
                Text("Add a habit in the app").font(p.font(13)).foregroundStyle(p.dim).frame(maxHeight: .infinity)
            }
            ForEach(entry.habits.prefix(limit), id: \.id) { h in
                HStack(spacing: 10) {
                    if rows == .regular { IconTile(icon: h.icon, size: 26, p: p) }
                    Text(h.name).font(p.font(14)).lineLimit(1)
                    if rows == .regular {
                        if h.off { Text("Day off").font(p.font(11)).foregroundStyle(p.dim) } else { Streak(days: h.streak, p: p) }
                    }
                    Spacer(minLength: 4)
                    if rows == .dots { WidgetWeek(data: h.progress, today: entry.today, shape: p.dots, ink: p.ink).frame(width: 90, height: 11) }
                    Button(intent: ToggleHabit(id: h.id)) {
                        WidgetCheck(done: h.done, partial: h.partial, tick: p.tick).frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxHeight: 30)
                .opacity(h.off && !h.done ? 0.5 : 1)
            }
            Spacer(minLength: 0)
            if entry.habits.count > limit && !p.receipt {
                Text("+\(entry.habits.count - limit) more").font(p.font(11)).foregroundStyle(p.dim)
            }
            LookFooter(p: p, text: (entry.habits.count > limit ? "+\(entry.habits.count - limit) MORE · " : "") + "TOTAL \(counted.filter(\.done).count)/\(counted.count)")
        }
        .widgetLook(p)
    }
}

// ---- Inbox ----------------------------------------------------------------------------------------

struct InboxEntry: TimelineEntry {
    let date: Date
    let today: Day
    let tasks: [Task]
    let config: InboxConfig
}

struct InboxProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> InboxEntry {
        InboxEntry(date: Date(), today: .today, tasks: Snapshot.sampleTasks(today: .today), config: InboxConfig())
    }
    func snapshot(for config: InboxConfig, in context: Context) async -> InboxEntry {
        context.isPreview ? placeholder(in: context) : await entry(config)
    }
    func timeline(for config: InboxConfig, in context: Context) async -> Timeline<InboxEntry> { untilMidnight(await entry(config)) }
    private func entry(_ config: InboxConfig) async -> InboxEntry {
        let tasks = (try? await Snapshot.store()?.db.read { try HabitStore.openTasks(in: $0) }) ?? []
        return InboxEntry(date: Date(), today: .today, tasks: tasks ?? [], config: config)
    }
}

struct InboxWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "inbox", intent: InboxConfig.self, provider: InboxProvider()) { InboxWidgetView(entry: $0) }
            .configurationDisplayName("Inbox")
            .description("Your tasks: check them off, add a new one.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct InboxWidgetView: View {
    let entry: InboxEntry
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetFamily) private var widgetFamily
    /// Set by the debug gallery, which isn't a real widget.
    var size: WidgetFamily? = nil
    private var family: WidgetFamily { size ?? widgetFamily }

    var body: some View {
        let p = WidgetPalette.resolve(entry.config.effectiveLook, darkText: entry.config.darkText, scheme: scheme)
        let limit = family == .systemLarge ? (p.receipt ? 7 : 8) : (p.receipt ? 2 : 3)
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Inbox").font(p.font(15, .bold))
                Text("\(entry.tasks.count)").font(p.font(13, .bold)).foregroundStyle(p.dim)
                Spacer()
                Link(destination: URL(string: "habitdots://add-task")!) {
                    Image("Icons/ui-plus").resizable().frame(width: 14, height: 14)
                        .frame(width: 24, height: 24).background(p.tile, in: Circle())
                }
            }
            if entry.tasks.isEmpty {
                Text("No tasks").font(p.font(13)).foregroundStyle(p.dim).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            ForEach(entry.tasks.prefix(limit), id: \.id) { t in
                let overdue = t.overdue(today: entry.today, now: ClockTime(now.hour ?? 0, now.minute ?? 0))
                let meta = [t.dueDate.flatMap { $0 == entry.today ? nil : Words.due($0, today: entry.today) }, t.dueTime?.description]
                    .compactMap { $0 }.joined(separator: "  ·  ")
                HStack(spacing: 10) {
                    Button(intent: CompleteTask(id: t.id ?? 0)) {
                        WidgetCheck(done: false, tick: p.tick).frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    // Todoist's priority flag, in the text ink: darker the more urgent.
                    if let a = Priority.alpha(t.priority) { Image("Icons/flag").resizable().frame(width: 14, height: 14).foregroundStyle(p.text).opacity(a) }
                    Text(t.title).font(p.font(14)).lineLimit(1)
                    Spacer(minLength: 4)
                    // Overdue is bold ink, never red.
                    if !meta.isEmpty { Text(meta).font(p.font(11, overdue ? .bold : .medium)).foregroundStyle(overdue ? p.text : p.dim).lineLimit(1) }
                }
                .frame(maxHeight: 30)
            }
            Spacer(minLength: 0)
            LookFooter(p: p, text: (entry.tasks.count > limit ? "+\(entry.tasks.count - limit) MORE · " : "") + "OPEN \(entry.tasks.count)")
        }
        .widgetLook(p)
        .widgetURL(URL(string: "habitdots://inbox")!)
    }
}
