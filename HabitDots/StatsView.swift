import SwiftUI
import GRDB
import HabitData
import HabitDesign
import HabitDomain

/// As little as says it: "All" is today's ring, the week, and each habit's momentum. A habit's own
/// chip is its momentum, its history and three numbers. With Pro; without it today's card is free
/// and the rest shows blurred behind an unlock card.
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
            HabitsCard(o: o)
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
                    Text("of due days").font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(palette.dim)
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
            Spacer().frame(height: 14)
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

/// Every habit on one line: its icon and name, its momentum as a small ring and an arrow for the
/// way it moved. No numbers; the ring is the number.
private struct HabitsCard: View {
    let o: OverviewStats
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
