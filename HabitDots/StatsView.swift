import SwiftUI
import GRDB
import HabitData
import HabitDesign
import HabitDomain

/// Progress you can feel more than read: "All" shows today's ring, the week against last, perfect
/// days, every habit's momentum, a year of dots and a few sentences the dots add up to. A habit's
/// own chip shows its momentum, history, totals, weekday pattern, months and milestones. With Pro;
/// without it today's card is free and the rest shows blurred behind an unlock card.
struct StatsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    private var pro: Bool { Store.shared.active }
    /// nil = all habits together.
    @State private var selected: Int64?
    @State private var done: Set<Day> = []
    @State private var stats: HabitStats?
    @State private var overview: OverviewStats?

    private var habits: [Tracker] { model.rows?.map(\.tracker) ?? [] }
    private var current: Tracker? { habits.first { $0.id == selected } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    RoundIcon(icon: "ui-arrow-left", label: "Back") { dismiss() }
                    Text("Statistics").font(Type.titleLarge)
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        chip(icon: "ui-squares-four", name: "All", on: current == nil) { selected = nil }
                        ForEach(habits, id: \.uuid) { t in
                            chip(icon: t.icon, name: t.name, on: t.id == current?.id) { selected = t.id }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                if habits.isEmpty {
                    Text("No habits yet").font(Type.bodyMedium).foregroundStyle(palette.dim)
                } else if current == nil, let overview {
                    VStack(spacing: 10) {
                        TodayCard(o: overview, today: model.today)
                        gated { overviewCards(overview) }
                    }
                    .id(0)
                    .transition(.opacity)
                } else if let stats {
                    gated { numbers(stats) }
                        .id(current?.id)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
            .animation(.easeOut(duration: 0.25), value: current?.id)
        }
        .scrollIndicators(.hidden)
        #if DEBUG
        // `-bottom`: open scrolled to the end, to check the lower cards in the simulator.
        .defaultScrollAnchor(CommandLine.arguments.contains("-bottom") ? .bottom : .top)
        #endif
        .background(palette.background)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: selected) { await load() }
        .onChange(of: model.rows) { _, _ in _Concurrency.Task { await load() } }
    }

    private func chip(icon: String, name: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image("Icons/\(icon)").resizable().frame(width: 16, height: 16)
                Text(name).font(Type.labelLarge).lineLimit(1).frame(maxWidth: 180)
            }
            .foregroundStyle(on ? palette.onInk : palette.ink)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(on ? palette.ink : palette.background, in: Capsule())
            .overlay(Capsule().stroke(palette.softBorder, lineWidth: 1))
            .animation(.easeOut(duration: 0.22), value: on)
        }
        .buttonStyle(.plain)
    }

    /// Pro: the real cards show blurred behind an unlock pill, so it's clear what they get.
    private func gated<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack(alignment: .top) {
            content()
                .blur(radius: pro ? 0 : 14).opacity(pro ? 1 : 0.6)
                .allowsHitTesting(pro)
            if !pro {
                Label { Text("Unlock with Pro").font(Type.titleSmall) } icon: { Image("Icons/ui-lock-simple").resizable().frame(width: 18, height: 18) }
                    .foregroundStyle(palette.onInk)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(palette.ink, in: Capsule())
                    .onTapGesture { Store.shared.paywall = true }
                    .padding(.top, 120)
            }
        }
    }

    private func overviewCards(_ o: OverviewStats) -> some View {
        VStack(spacing: 10) {
            PerfectDaysCard(o: o)
            HabitsCard(o: o, today: model.today)
            YearCard(values: o.year, today: model.today)
            if !o.insights.isEmpty { InsightsCard(lines: o.insights) }
            Spacer().frame(height: 14)
        }
    }

    private func numbers(_ s: HabitStats) -> some View {
        VStack(spacing: 10) {
            MomentumCard(stats: s)
            SectionCard { LabeledHeatmap(data: Dictionary(uniqueKeysWithValues: done.map { ($0, 1.0) }), today: model.today) }
            // Bento: one big tile with the headline number, smaller tiles around it.
            HStack(spacing: 10) {
                Tile {
                    Text("Completions").font(Type.labelMedium).foregroundStyle(palette.dim)
                    Spacer(minLength: 12)
                    Counting(value: s.completions).font(Type.displaySmall)
                    Text("due days done").font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(palette.dim)
                    Bar(fraction: s.rate).padding(.top, 10)
                }
                VStack(spacing: 10) {
                    Tile {
                        HStack(spacing: 3) {
                            Image("Icons/ui-fire-fill").resizable().frame(width: 24, height: 24)
                            Counting(value: s.current).font(Type.headlineSmall)
                        }
                        Text("Streak").font(Type.labelMedium).foregroundStyle(palette.dim)
                    }
                    Tile {
                        Counting(value: s.best).font(Type.headlineSmall)
                        Text("Best streak").font(Type.labelMedium).foregroundStyle(palette.dim)
                    }
                }
            }
            .frame(height: 190)
            WeekdayCard(rates: s.byWeekday)
            MonthsCard(months: s.perMonth)
            MilestonesCard(current: s.current, best: s.best)
            VStack(spacing: 4) {
                Text(verbatim: "Since \(Words.date(s.since)), \(String(s.since.year)) · \(s.since.distance(to: model.today) + 1) days")
                if let g = s.longestGap {
                    Text(verbatim: "Longest gap: \(g.days) \(g.days == 1 ? "day" : "days"), ending \(Words.date(g.end))")
                }
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(palette.dim)
            .frame(maxWidth: .infinity).padding(.top, 6).padding(.bottom, 24)
        }
    }

    /// One habit's history, or every habit's for "All".
    private func load() async {
        let today = model.today
        if let t = current, let id = t.id {
            let (days, rest) = (try? await model.store.db.read { db in
                (try Day.fetchAll(db, sql: "SELECT date FROM entry WHERE trackerId = ? AND value >= ?", arguments: [id, t.target]),
                 try Day.fetchAll(db, sql: "SELECT date FROM entry WHERE trackerId = ? AND value = ?", arguments: [id, Entry.rest]))
            }) ?? ([], [])
            done = Set(days)
            stats = HabitStats(done: done, created: .from(millis: t.createdAt), rule: t.rule, today: today, rest: Set(rest))
        } else {
            let trackers = habits
            let streaks = Dictionary((model.rows ?? []).map { ($0.id, $0.streak) }, uniquingKeysWith: { a, _ in a })
            let from = today - AppModel.historyDays
            overview = try? await model.store.db.read { db in
                let byHabit = Dictionary(grouping: try Entry.filter(Column("date") >= from).fetchAll(db), by: \.trackerId)
                return OverviewStats(trackers.map { t in
                    let mine = byHabit[t.id ?? -1] ?? []
                    return HabitHistory(name: t.name, icon: t.icon, done: Set(mine.filter { t.isDone($0.value) }.map(\.date)), rest: mine.restDays,
                                        created: .from(millis: t.createdAt), rule: t.rule, streak: streaks[t.id ?? 0] ?? 0)
                }, today: today)
            }
        }
    }
}

// MARK: - All habits

/// Today as a ring that fills as habits get done, the last seven days as little cups, and one line
/// for the week. A perfect day gets confetti once the ring closes.
private struct TodayCard: View {
    let o: OverviewStats
    let today: Day
    @Environment(\.palette) private var palette
    @Environment(Confetti.self) private var confetti
    @State private var fill = 0.0
    @State private var celebrated = false

    private var perfect: Bool { o.todayDue > 0 && o.todayDone == o.todayDue }
    private var title: String { o.todayDue == 0 ? "Nothing due today" : perfect ? "All done today" : "Today" }
    private var delta: Int? { o.lastWeek.map { Int(((o.week - $0) * 100).rounded()) } }

    var body: some View {
        SectionCard {
            HStack(spacing: 20) {
                GeometryReader { geo in
                    ZStack {
                        Circle().stroke(palette.tint, lineWidth: 11)
                        Circle().trim(from: 0, to: fill)
                            .stroke(palette.ink, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Counting(value: o.todayDone).font(Type.headlineMedium)
                            Text("/\(o.todayDue)").font(Type.titleSmall).foregroundStyle(palette.dim)
                        }
                    }
                    .onAppear { animate(in: geo) }
                    .onChange(of: o.todayDone) { _, _ in animate(in: geo) }
                }
                .frame(width: 116, height: 116)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(Type.titleMedium)
                    HStack(spacing: 5) {
                        ForEach(0..<7, id: \.self) { i in
                            DayCup(value: o.weekDays[i], day: today - (6 - i), isToday: i == 6)
                        }
                    }
                    HStack(spacing: 5) {
                        Text("\(Int((o.week * 100).rounded()))% this week")
                        if let delta, delta != 0 {
                            Image("Icons/\(delta > 0 ? "ui-trend-up" : "ui-trend-down")").resizable().frame(width: 12, height: 12)
                            Text("\(abs(delta)) vs last")
                        }
                    }
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle((delta ?? 0) >= 0 ? palette.ink : palette.dim)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(palette.tile, in: Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func animate(in geo: GeometryProxy) {
        let target = o.todayDue == 0 ? 0 : Double(o.todayDone) / Double(o.todayDue)
        withAnimation(.spring(response: 1.1, dampingFraction: 0.85)) { fill = target }
        guard perfect, !celebrated else { return }
        celebrated = true
        let f = geo.frame(in: .global)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { confetti.fire(at: CGPoint(x: f.midX, y: f.midY)) }
    }
}

/// One day of the week as a small cup that fills from the bottom: full means every due habit was
/// done, half means half of them. A day with nothing due is an empty outline. Today is ringed.
private struct DayCup: View {
    let value: Double?
    let day: Day
    let isToday: Bool
    @Environment(\.palette) private var palette
    @State private var reveal = 0.0

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(value == nil ? .clear : palette.tint)
                if let value {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(palette.ink)
                        .frame(height: 24 * min(value, 1) * reveal)
                        .mask(RoundedRectangle(cornerRadius: 6, style: .continuous).frame(height: 24).frame(maxHeight: .infinity, alignment: .bottom))
                }
            }
            .frame(width: 22, height: 24)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isToday ? palette.ink : value == nil ? palette.hairline : .clear, style: StrokeStyle(lineWidth: 1.5, dash: value == nil && !isToday ? [2, 2] : [])))
            Text(String(Words.weekdaysShort[day.weekday - 1].prefix(1)))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(isToday ? palette.ink : palette.dim)
        }
        .onAppear { withAnimation(.spring(response: 0.8, dampingFraction: 0.8).delay(Double(6 - (6 - (day.epochDay % 7))) * 0.02)) { reveal = 1 } }
        .onChange(of: value) { _, _ in withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { reveal = 1 } }
    }
}

/// The last 30 days as dots, solid where every due habit was done. Dots pop in one after another.
private struct PerfectDaysCard: View {
    let o: OverviewStats
    @Environment(\.palette) private var palette
    @State private var shown = false

    private var count: Int { o.perfectDays.filter { $0 }.count }

    var body: some View {
        SectionCard {
            HStack(alignment: .firstTextBaseline) {
                Text("Perfect days").font(Type.titleSmall)
                Spacer()
                Text("\(count) of 30").font(Type.labelSmall).foregroundStyle(palette.dim)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 15), spacing: 8) {
                ForEach(0..<30, id: \.self) { i in
                    let hit = o.perfectDays[i]
                    Circle().fill(hit ? palette.ink : palette.tint)
                        .overlay(Circle().stroke(i == 29 && !hit ? palette.ink : .clear, lineWidth: 1.5))
                        .aspectRatio(1, contentMode: .fit)
                        .scaleEffect(shown ? 1 : 0.3).opacity(shown ? 1 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(Double(i) * 0.018), value: shown)
                }
            }
            .padding(.top, 14)
            HStack(spacing: 6) {
                Image("Icons/ui-sparkle-fill").resizable().frame(width: 14, height: 14)
                Text(o.perfectWeeks > 0 ? "\(o.perfectWeeks) perfect \(o.perfectWeeks == 1 ? "week" : "weeks") in the last twelve"
                                        : "A perfect day is every habit done. A week of them is next.")
            }
            .font(Type.labelMedium).foregroundStyle(o.perfectWeeks > 0 ? palette.ink : palette.dim)
            .padding(.top, 14)
        }
        .onAppear { shown = true }
    }
}

/// Every habit on one line: its icon and name, the last 30 days as a chain, its momentum as a
/// small ring and an arrow for the way it moved. No numbers; the ring is the number.
private struct HabitsCard: View {
    let o: OverviewStats
    let today: Day
    @Environment(\.palette) private var palette

    var body: some View {
        SectionCard {
            HStack(alignment: .firstTextBaseline) {
                Text("Habits").font(Type.titleSmall)
                Spacer()
                Text("Last 30 days").font(Type.labelSmall).foregroundStyle(palette.dim)
            }
            VStack(spacing: 12) {
                ForEach(Array(o.habits.enumerated()), id: \.offset) { _, h in
                    HStack(spacing: 10) {
                        HabitIconTile(icon: h.icon, size: 28)
                        Text(h.name).font(Type.labelLarge).lineLimit(1)
                        Spacer(minLength: 8)
                        ChainStrip(data: Dictionary(uniqueKeysWithValues: h.days.enumerated().compactMap { i, d in d ? (today - (29 - i), 1.0) : nil }), today: today)
                            .frame(width: 84)
                        MiniRing(value: h.momentum)
                        trend(h)
                    }
                }
            }
            .padding(.top, 14)
        }
    }

    private func trend(_ h: OverviewStats.HabitLine) -> some View {
        let delta = h.before.map { Int(((h.momentum - $0) * 100).rounded()) }
        let icon = delta == nil ? "ui-sparkle-fill" : delta! >= 3 ? "ui-trend-up" : delta! <= -3 ? "ui-trend-down" : "ui-minus"
        return Image("Icons/\(icon)").resizable().frame(width: 14, height: 14)
            .foregroundStyle((delta ?? 0) >= 0 ? palette.ink : palette.dim)
            .frame(width: 16)
    }
}

private struct MiniRing: View {
    let value: Double
    @Environment(\.palette) private var palette
    @State private var fill = 0.0
    var body: some View {
        ZStack {
            Circle().stroke(palette.tint, lineWidth: 3.5)
            Circle().trim(from: 0, to: fill).stroke(palette.ink, style: StrokeStyle(lineWidth: 3.5, lineCap: .round)).rotationEffect(.degrees(-90))
        }
        .frame(width: 22, height: 22)
        .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.85)) { fill = min(max(value, 0), 1) } }
        .onChange(of: value) { _, v in withAnimation(.spring(response: 0.9, dampingFraction: 0.85)) { fill = min(max(v, 0), 1) } }
    }
}

/// 365 days, every habit folded in: a column per week, Monday on top. Darker is more of the day's
/// habits done; a bare dot is a day with nothing due. Draws itself in from the left.
private struct YearCard: View {
    let values: [Double?]
    let today: Day
    @Environment(\.palette) private var palette
    @State private var reveal = 0.0

    var body: some View {
        SectionCard {
            HStack(alignment: .firstTextBaseline) {
                Text("Year in dots").font(Type.titleSmall)
                Spacer()
                Text("Last 365 days").font(Type.labelSmall).foregroundStyle(palette.dim)
            }
            Canvas { ctx, size in
                let first = today - 364
                let lead = first.weekday - 1
                let cols = (lead + 365 + 6) / 7
                let gap: CGFloat = 2
                let cell = (size.width - CGFloat(cols - 1) * gap) / CGFloat(cols)
                let top: CGFloat = 14
                var lastLabel = -3
                for i in 0..<365 {
                    let pos = lead + i, col = pos / 7, row = pos % 7
                    let x = CGFloat(col) * (cell + gap), y = top + CGFloat(row) * (cell + gap)
                    let day = first + i
                    if row == 0 || i == 0, day.day <= 7, col - lastLabel >= 3 {
                        lastLabel = col
                        ctx.draw(Text(String(Words.months[day.month - 1].prefix(3))).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(palette.dim),
                                 at: CGPoint(x: x, y: 0), anchor: .topLeading)
                    }
                    guard CGFloat(x) <= size.width * reveal else { continue }
                    let rect = CGRect(x: x, y: y, width: cell, height: cell)
                    if let v = values[i] {
                        let alpha = v <= 0 ? 0.12 : v < 0.5 ? 0.35 : v < 1 ? 0.65 : 1
                        ctx.fill(Path(roundedRect: rect, cornerRadius: cell * 0.25), with: .color(palette.ink.opacity(alpha)))
                    } else {
                        ctx.fill(Path(ellipseIn: rect.insetBy(dx: cell * 0.36, dy: cell * 0.36)), with: .color(palette.hairline))
                    }
                }
            }
            .frame(height: 14 + 7 * 6 + 6 * 2)
            .padding(.top, 10)
            .onAppear { withAnimation(.easeOut(duration: 1.0)) { reveal = 1 } }
        }
    }
}

/// Two or three sentences the numbers add up to, each with a spark in front.
private struct InsightsCard: View {
    let lines: [String]
    @Environment(\.palette) private var palette
    var body: some View {
        SectionCard {
            Text("Insights").font(Type.titleSmall)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 10) {
                        Image("Icons/ui-sparkle-fill").resizable().frame(width: 14, height: 14).padding(.top, 3)
                        Text(line).font(Type.bodyMedium).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 12)
        }
    }
}

// MARK: - One habit

/// The headline: a big ring with the last 30 days' rate, and which way it moved since the 30 before.
private struct MomentumCard: View {
    let stats: HabitStats
    @Environment(\.palette) private var palette
    @State private var fill = 0.0

    private var percent: Int { Int((stats.momentum * 100).rounded()) }
    /// Change in points since the 30 days before; nil for a habit younger than that.
    private var delta: Int? { stats.momentumBefore.map { percent - Int(($0 * 100).rounded()) } }

    var body: some View {
        SectionCard {
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(palette.tint, lineWidth: 11)
                    Circle().trim(from: 0, to: fill)
                        .stroke(palette.ink, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Counting(value: percent).font(Type.headlineMedium)
                        Text("%").font(Type.titleSmall).foregroundStyle(palette.dim)
                    }
                }
                .frame(width: 116, height: 116)
                .onAppear { withAnimation(.spring(response: 1.1, dampingFraction: 0.85)) { fill = min(max(stats.momentum, 0), 1) } }
                .onChange(of: stats.momentum) { _, m in withAnimation(.spring(response: 1.1, dampingFraction: 0.85)) { fill = min(max(m, 0), 1) } }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Momentum").font(Type.titleMedium)
                    Text("Last 30 days").font(Type.bodyMedium).foregroundStyle(palette.dim)
                    Spacer(minLength: 4)
                    HStack(spacing: 5) {
                        if let delta {
                            Image("Icons/\(delta > 0 ? "ui-trend-up" : delta < 0 ? "ui-trend-down" : "ui-minus")").resizable().frame(width: 14, height: 14)
                            Text(delta == 0 ? "Same as the 30 before" : "\(delta > 0 ? "+" : "")\(delta) pts vs the 30 before")
                        } else {
                            Image("Icons/ui-sparkle-fill").resizable().frame(width: 14, height: 14)
                            Text("Your first 30 days")
                        }
                    }
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle((delta ?? 0) >= 0 ? palette.ink : palette.dim)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(palette.tile, in: Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Seven bars, Monday first: where the habit holds and where it slips. The strongest day is solid;
/// the bars say it, so there are no numbers.
private struct WeekdayCard: View {
    let rates: [Double?]
    @Environment(\.palette) private var palette
    @State private var reveal = 0.0

    /// The day(s) with the top rate; several when tied. Nothing stands out while every day is at zero.
    private var best: Set<Int> {
        let on = rates.enumerated().compactMap { i, r in r.map { (i, $0) } }
        guard let top = on.map(\.1).max(), top > 0 else { return [] }
        return Set(on.filter { $0.1 == top }.map(\.0))
    }
    private var caption: String? {
        let days = best.sorted()
        if days.count == 1 { return "Strongest on \(Words.weekdaysLong[days[0]])s" }
        if days.count > 1 && days.count < 7 { return "Strongest: " + days.map { Words.weekdaysShort[$0] }.joined(separator: ", ") }
        return nil
    }

    var body: some View {
        SectionCard {
            HStack(alignment: .firstTextBaseline) {
                Text("By weekday").font(Type.titleSmall)
                Spacer()
                if let caption { Text(caption).font(Type.labelSmall).foregroundStyle(palette.dim) }
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 8) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(palette.tint)
                            if let r = rates[i] {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(palette.ink.opacity(best.contains(i) ? 1 : 0.45))
                                    .frame(height: max(6, 72 * min(r, 1) * reveal))
                            } else {
                                Rectangle().fill(palette.dim.opacity(0.5)).frame(width: 10, height: 1.5).padding(.bottom, 35)
                            }
                        }
                        .frame(height: 72)
                        Text(Words.weekdaysShort[i]).font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(rates[i] == nil ? palette.dim.opacity(0.6) : best.contains(i) ? palette.ink : palette.dim)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 14)
            .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.8)) { reveal = 1 } }
        }
    }
}

/// Twelve bars, one a month, the best one solid with its count on top. Bars rise on first show.
private struct MonthsCard: View {
    let months: [(month: Day, count: Int)]
    @Environment(\.palette) private var palette
    @State private var reveal = 0.0

    private var peak: Int? { months.enumerated().max { $0.element.count < $1.element.count }.flatMap { $0.element.count > 0 ? $0.offset : nil } }
    private var top: CGFloat { CGFloat(max(months.map(\.count).max() ?? 0, 1)) }

    var body: some View {
        SectionCard {
            HStack(alignment: .firstTextBaseline) {
                Text("By month").font(Type.titleSmall)
                Spacer()
                if let peak { Text("Best: \(Words.months[months[peak].month.month - 1])").font(Type.labelSmall).foregroundStyle(palette.dim) }
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(months.enumerated()), id: \.offset) { i, m in
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottom) {
                            if i == peak {
                                Text("\(m.count)").font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(palette.onInk)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(palette.ink, in: Capsule())
                                    .offset(y: -(max(6, 96 * CGFloat(m.count) / top * reveal) + 6))
                                    .opacity(reveal)
                            }
                            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(palette.tint)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(palette.ink.opacity(i == peak ? 1 : 0.45))
                                .frame(height: m.count == 0 ? 0 : max(6, 96 * CGFloat(m.count) / top * reveal))
                        }
                        .frame(height: 96)
                        Text(i % 2 == 1 ? String(Words.months[m.month.month - 1].prefix(3)) : " ")
                            .font(.system(size: 9, weight: .medium, design: .monospaced)).lineLimit(1).fixedSize().foregroundStyle(palette.dim)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 30)
            .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.8)) { reveal = 1 } }
        }
    }
}

/// The streak milestones, reached ones filled in; the next one says how far it is. 66 days is the
/// one that matters: that's about how long a habit takes to form.
private struct MilestonesCard: View {
    let current: Int
    let best: Int
    @Environment(\.palette) private var palette
    private let marks = [7, 30, 66, 100, 200, 365]

    var body: some View {
        SectionCard {
            HStack(alignment: .firstTextBaseline) {
                Text("Milestones").font(Type.titleSmall)
                Spacer()
                if let next = marks.first(where: { $0 > current }) {
                    Text("\(next - current) days to \(next)").font(Type.labelSmall).foregroundStyle(palette.dim)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                ForEach(marks, id: \.self) { m in
                    let hit = best >= m
                    VStack(spacing: 4) {
                        Text("\(m)")
                            .font(.system(size: m >= 100 ? 11 : 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(hit ? palette.onInk : palette.dim)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(hit ? palette.ink : .clear))
                            .overlay(Circle().stroke(hit ? .clear : palette.outline, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
                        Text(m == 66 ? "formed" : " ").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(palette.dim)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 14)
        }
    }
}

private struct Tile<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(palette.surfaceLow, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).stroke(palette.softBorder, lineWidth: 1))
    }
}

/// Counts up from 0 on first show (800 ms ease-out), then glides between values.
private struct Counting: View {
    let value: Int
    @State private var shown = 0.0
    var body: some View {
        CountingText(shown)
            .onAppear { withAnimation(.easeOut(duration: 0.8)) { shown = Double(value) } }
            .onChange(of: value) { _, v in withAnimation(.easeOut(duration: 0.8)) { shown = Double(v) } }
    }
}

/// Thin progress bar that fills in on first show.
private struct Bar: View {
    let fraction: Double
    @State private var fill = 0.0
    @Environment(\.palette) private var palette
    var body: some View {
        GeometryReader { geo in
            Capsule().fill(palette.ink.opacity(0.12))
                .overlay(alignment: .leading) { Capsule().fill(palette.ink).frame(width: geo.size.width * fill) }
        }
        .frame(height: 6)
        .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.8)) { fill = min(max(fraction, 0), 1) } }
        .onChange(of: fraction) { _, f in withAnimation(.spring(response: 0.9, dampingFraction: 0.8)) { fill = min(max(f, 0), 1) } }
    }
}
