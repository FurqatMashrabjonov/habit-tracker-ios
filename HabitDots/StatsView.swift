import SwiftUI
import GRDB
import HabitData
import HabitDesign
import HabitDomain

/// "Your progress in numbers": pick a habit, see its momentum, history, totals, weekday pattern, a
/// monthly curve and milestones. With Pro; without it the real numbers show blurred behind an unlock
/// card, so it's clear what they get.
struct StatsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    private var pro: Bool { Store.shared.active }
    @State private var selected: Int64?
    @State private var done: Set<Day> = []
    @State private var stats: HabitStats?

    private var habits: [Tracker] { model.rows?.map(\.tracker) ?? [] }
    private var current: Tracker? { habits.first { $0.id == selected } ?? habits.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    RoundIcon(icon: "ui-arrow-left", label: "Back") { dismiss() }
                    Text("Statistics").font(Type.titleLarge)
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(habits, id: \.uuid) { t in
                            let on = t.id == current?.id
                            Button { selected = t.id } label: {
                                HStack(spacing: 6) {
                                    Image("Icons/\(t.icon)").resizable().frame(width: 16, height: 16)
                                    Text(t.name).font(Type.labelLarge).lineLimit(1).frame(maxWidth: 180)
                                }
                                .foregroundStyle(on ? palette.onInk : palette.ink)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(on ? palette.ink : palette.background, in: Capsule())
                                .overlay(Capsule().stroke(palette.softBorder, lineWidth: 1))
                                .animation(.easeOut(duration: 0.22), value: on)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                if habits.isEmpty {
                    Text("No habits yet").font(Type.bodyMedium).foregroundStyle(palette.dim)
                } else if let stats {
                    ZStack(alignment: .top) {
                        numbers(stats)
                            .blur(radius: pro ? 0 : 14).opacity(pro ? 1 : 0.6)
                            .allowsHitTesting(pro)
                            .id(current?.id)
                            .transition(.opacity)
                        if !pro {
                            Label { Text("Unlock with Pro").font(Type.titleSmall) } icon: { Image("Icons/ui-lock-simple").resizable().frame(width: 18, height: 18) }
                                .foregroundStyle(palette.onInk)
                                .padding(.horizontal, 20).padding(.vertical, 12)
                                .background(palette.ink, in: Capsule())
                                .onTapGesture { Store.shared.paywall = true }
                                .padding(.top, 120)
                        }
                    }
                    .animation(.easeOut(duration: 0.25), value: current?.id)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        #if DEBUG
        // `-bottom`: open scrolled to the end, to check the lower cards in the simulator.
        .defaultScrollAnchor(CommandLine.arguments.contains("-bottom") ? .bottom : .top)
        #endif
        .background(palette.background)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: current?.id) { await load() }
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
                    Text("\(Int((s.rate * 100).rounded()))% of due days").font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(palette.dim)
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
            SectionCard {
                Text("Completions / month").font(Type.titleSmall)
                MonthCurve(values: s.perMonth.map(\.count)).frame(height: 120).padding(.top, 22)
                HStack {
                    ForEach(Array(s.perMonth.enumerated()), id: \.offset) { i, m in
                        Text(i % 2 == 1 ? String(Words.months[m.month.month - 1].prefix(3)) : "")
                            .font(Type.labelSmall).foregroundStyle(palette.dim).lineLimit(1).fixedSize().frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 6)
            }
            MilestonesCard(current: s.current, best: s.best)
            Text(verbatim: "Since \(Words.date(s.since)), \(String(s.since.year)) · \(s.since.distance(to: model.today) + 1) days")
                .font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(palette.dim)
                .frame(maxWidth: .infinity).padding(.top, 6).padding(.bottom, 24)
        }
    }

    /// Only the selected habit's history is read.
    private func load() async {
        guard let t = current, let id = t.id else { stats = nil; return }
        let today = model.today
        let (days, rest) = (try? await model.store.db.read { db in
            (try Day.fetchAll(db, sql: "SELECT date FROM entry WHERE trackerId = ? AND value >= ?", arguments: [id, t.target]),
             try Day.fetchAll(db, sql: "SELECT date FROM entry WHERE trackerId = ? AND value = ?", arguments: [id, Entry.rest]))
        }) ?? ([], [])
        done = Set(days)
        stats = HabitStats(done: done, created: .from(millis: t.createdAt), rule: t.rule, today: today, rest: Set(rest))
    }
}

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

/// Seven bars, Monday first: where the habit holds and where it slips. The strongest day is solid.
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
                        Text(rates[i].map { "\(Int(($0 * 100).rounded()))" } ?? "–")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(rates[i] == nil ? palette.dim.opacity(0.6) : best.contains(i) ? palette.ink : palette.dim)
                            .opacity(reveal)
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

/// The streak milestones, reached ones filled in; the next one says how far it is.
private struct MilestonesCard: View {
    let current: Int
    let best: Int
    @Environment(\.palette) private var palette
    private let marks = [7, 30, 50, 100, 200, 365]

    var body: some View {
        SectionCard {
            HStack(alignment: .firstTextBaseline) {
                Text("Milestones").font(Type.titleSmall)
                Spacer()
                if let next = marks.first(where: { $0 > current }) {
                    Text("\(next - current) days to \(next)").font(Type.labelSmall).foregroundStyle(palette.dim)
                }
            }
            HStack(spacing: 8) {
                ForEach(marks, id: \.self) { m in
                    let hit = best >= m
                    Text("\(m)")
                        .font(.system(size: m >= 100 ? 11 : 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(hit ? palette.onInk : palette.dim)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(hit ? palette.ink : .clear))
                        .overlay(Circle().stroke(hit ? .clear : palette.outline, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
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

/// Smooth area curve of monthly counts that draws itself in from the left, a dot on each month and
/// the best month's count written above it.
private struct MonthCurve: View {
    let values: [Int]
    @State private var reveal = 0.0
    @Environment(\.palette) private var palette
    var body: some View {
        GeometryReader { geo in
            let pts = CurveShape.points(values, in: CGRect(origin: .zero, size: geo.size))
            let peak = values.enumerated().max { $0.element < $1.element }
            ZStack(alignment: .topLeading) {
                CurveShape(values: values, closed: true)
                    .fill(LinearGradient(colors: [palette.ink.opacity(0.25), palette.ink.opacity(0)], startPoint: .top, endPoint: .bottom))
                CurveShape(values: values, closed: false)
                    .stroke(palette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                ForEach(Array(pts.enumerated()), id: \.offset) { i, p in
                    Circle().fill(i == peak?.offset ? palette.ink : palette.background)
                        .overlay(Circle().stroke(palette.ink, lineWidth: 1.5))
                        .frame(width: i == peak?.offset ? 8 : 5, height: i == peak?.offset ? 8 : 5)
                        .position(p)
                }
                if let peak, peak.element > 0, pts.indices.contains(peak.offset) {
                    Text("\(peak.element)").font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.onInk)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(palette.ink, in: Capsule())
                        .position(x: min(max(pts[peak.offset].x, 16), geo.size.width - 16), y: pts[peak.offset].y - 18)
                }
            }
            .mask(alignment: .leading) { Rectangle().frame(width: geo.size.width * reveal).padding(.top, -30) }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { reveal = 1 } }
    }
}

private struct CurveShape: Shape {
    let values: [Int]
    let closed: Bool

    static func points(_ values: [Int], in r: CGRect) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let top = CGFloat(max(values.max() ?? 0, 1))
        let step = r.width / CGFloat(values.count - 1)
        return values.enumerated().map { CGPoint(x: CGFloat($0) * step, y: r.height - CGFloat($1) / top * r.height * 0.9) }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        let pts = Self.points(values, in: r)
        guard !pts.isEmpty else { return p }
        p.move(to: pts[0])
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i], mx = (a.x + b.x) / 2
            p.addCurve(to: b, control1: CGPoint(x: mx, y: a.y), control2: CGPoint(x: mx, y: b.y))
        }
        if closed { p.addLine(to: CGPoint(x: r.width, y: r.height)); p.addLine(to: CGPoint(x: 0, y: r.height)); p.closeSubpath() }
        return p
    }
}
