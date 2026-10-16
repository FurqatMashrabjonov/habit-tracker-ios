import SwiftUI
import GRDB
import HabitData
import HabitDesign
import HabitDomain

/// "Your progress in numbers": pick a habit, see its history, totals and a monthly curve. With Pro;
/// without it the real numbers show blurred behind an unlock card, so it's clear what they get.
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
        .background(palette.background)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: current?.id) { await load() }
    }

    private func numbers(_ s: HabitStats) -> some View {
        VStack(spacing: 10) {
            SectionCard { FitHeatmap(data: Dictionary(uniqueKeysWithValues: done.map { ($0, 1.0) }), today: model.today, targetCell: 15) }
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
            SectionCard {
                Text("Completions / month").font(Type.titleSmall)
                MonthCurve(values: s.perMonth.map(\.count)).frame(height: 120).padding(.top, 14)
                HStack {
                    ForEach(Array(s.perMonth.enumerated()), id: \.offset) { i, m in
                        Text(i % 2 == 1 ? String(Words.months[m.month.month - 1].prefix(3)) : "")
                            .font(Type.labelSmall).foregroundStyle(palette.dim).lineLimit(1).fixedSize().frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 6)
            }
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

/// Smooth area curve of monthly counts that draws itself in from the left.
private struct MonthCurve: View {
    let values: [Int]
    @State private var reveal = 0.0
    @Environment(\.palette) private var palette
    var body: some View {
        ZStack {
            CurveShape(values: values, closed: true)
                .fill(LinearGradient(colors: [palette.ink.opacity(0.25), palette.ink.opacity(0)], startPoint: .top, endPoint: .bottom))
            CurveShape(values: values, closed: false)
                .stroke(palette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .mask(alignment: .leading) { GeometryReader { geo in Rectangle().frame(width: geo.size.width * reveal) } }
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { reveal = 1 } }
    }
}

private struct CurveShape: Shape {
    let values: [Int]
    let closed: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        guard values.count >= 2 else { return p }
        let top = CGFloat(max(values.max() ?? 0, 1))
        let step = r.width / CGFloat(values.count - 1)
        let pts = values.enumerated().map { CGPoint(x: CGFloat($0) * step, y: r.height - CGFloat($1) / top * r.height * 0.9) }
        p.move(to: pts[0])
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i], mx = (a.x + b.x) / 2
            p.addCurve(to: b, control1: CGPoint(x: mx, y: a.y), control2: CGPoint(x: mx, y: b.y))
        }
        if closed { p.addLine(to: CGPoint(x: r.width, y: r.height)); p.addLine(to: CGPoint(x: 0, y: r.height)); p.closeSubpath() }
        return p
    }
}
