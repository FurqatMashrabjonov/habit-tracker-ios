import SwiftUI
import HabitDomain
#if os(iOS)
import WidgetKit
#endif

/*
 * Widgets can't run a Canvas (their views are archived and drawn later), so the check and the dots
 * come again as plain shapes, with the same proportions as `drawCheck` and `drawCell`.
 */

/// How cells are inked beyond their shape: `outline` draws undone days as rings, `glow` lights done ones (widget looks).
public struct DotInk: Sendable, Equatable {
    public var outline = false
    public var glow = false
    public init(outline: Bool = false, glow: Bool = false) { self.outline = outline; self.glow = glow }
    public static let plain = DotInk()
}

/// The dots of one state drawn with an ink: a plain fill, rings, or a fill with a halo behind it.
struct InkedCells: View {
    let cells: [CGRect]
    let corner: CGFloat
    let level: Double // 0 empty, 0.5 partial, 1 done
    let ink: DotInk
    let faint: Double // opacity of an empty plain fill
    var body: some View {
        if cells.isEmpty { EmptyView() } else if ink.outline && level < 1 {
            let w = max(1, min(2, (cells[0].width * 0.12)))
            ZStack(alignment: .topLeading) {
                if level > 0 { CellsShape(cells: cells, corner: corner).fill(.primary.opacity(0.22)) }
                CellsShape(cells: cells.map { $0.insetBy(dx: w / 2, dy: w / 2) }, corner: corner).stroke(.primary.opacity(level > 0 ? 0.8 : 0.4), lineWidth: w)
            }
        } else if level >= 1 {
            ZStack(alignment: .topLeading) {
                if ink.glow { let g = cells[0].width * 0.35; CellsShape(cells: cells.map { $0.insetBy(dx: -g, dy: -g) }, corner: corner).fill(.primary.opacity(0.28)) }
                CellsShape(cells: cells, corner: corner).fill(.primary).widgetAccentableIfAvailable()
            }
        } else {
            CellsShape(cells: cells, corner: corner).fill(.primary.opacity(level > 0 ? 0.45 : faint))
        }
    }
}

/// Rounded cells, one path, filled once: a whole wall of dots costs one view.
public struct CellsShape: Shape {
    public let cells: [CGRect]
    public let corner: CGFloat // fraction of the cell
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        for c in cells { p.addRoundedRect(in: c, cornerSize: CGSize(width: c.width * corner, height: c.width * corner), style: .continuous) }
        return p
    }
}

/// History as weeks of 7 dots, as many weeks as fit, today last; empty days faint, partial ones mid,
/// done ones solid.
public struct WidgetDots: View {
    public let data: [Day: Double]
    public let today: Day
    public var shape: DotShape = .square
    public var maxCell: CGFloat = 16
    public var ink: DotInk = .plain
    /// Days that are neither due nor done, drawn fainter than empty ones.
    public var off: (Day) -> Bool = { _ in false }
    public init(data: [Day: Double], today: Day, shape: DotShape = .square, maxCell: CGFloat = 16, ink: DotInk = .plain, off: @escaping (Day) -> Bool = { _ in false }) {
        self.data = data; self.today = today; self.shape = shape; self.maxCell = maxCell; self.ink = ink; self.off = off
    }

    public var body: some View {
        GeometryReader { geo in
            let fit = min(geo.size.height / 8.2, maxCell)
            let weeks = max(Int((geo.size.width + fit * 0.2) / (fit * 1.2)), 1)
            let cell = min(geo.size.width / (CGFloat(weeks) * 1.2 - 0.2), geo.size.height / 8.2)
            let start = today.weekStart - 7 * (weeks - 1)
            let s = cell * shape.grow
            let groups = Self.cells(data: data, from: start, today: today, step: cell * 1.2, size: s, off: off)
            ZStack(alignment: .topLeading) {
                CellsShape(cells: groups.off, corner: shape.radius).fill(.primary.opacity(0.07))
                InkedCells(cells: groups.empty, corner: shape.radius, level: 0, ink: ink, faint: emptyAlpha)
                InkedCells(cells: groups.partial, corner: shape.radius, level: 0.5, ink: ink, faint: emptyAlpha)
                InkedCells(cells: groups.done, corner: shape.radius, level: 1, ink: ink, faint: emptyAlpha)
            }
            .frame(width: CGFloat(weeks) * cell * 1.2 - cell * 0.2, height: cell * 8.2, alignment: .topLeading)
        }
    }

    static func cells(data: [Day: Double], from: Day, today: Day, step: CGFloat, size: CGFloat, off: (Day) -> Bool)
        -> (empty: [CGRect], partial: [CGRect], done: [CGRect], off: [CGRect]) {
        var empty: [CGRect] = [], partial: [CGRect] = [], done: [CGRect] = [], offDays: [CGRect] = []
        var d = from
        while d <= today {
            let i = d - from
            let r = CGRect(x: CGFloat(i / 7) * step, y: CGFloat(i % 7) * step, width: size, height: size)
            let v = data[d] ?? 0
            if v >= 1 { done.append(r) } else if v > 0 { partial.append(r) } else if off(d) { offDays.append(r) } else { empty.append(r) }
            d = d + 1
        }
        return (empty, partial, done, offDays)
    }
}

/// The last `days` days (seven by default) as one row of big dots.
public struct WidgetWeek: View {
    public let data: [Day: Double]
    public let today: Day
    public var shape: DotShape = .square
    public var ink: DotInk = .plain
    public var days = 7
    public init(data: [Day: Double], today: Day, shape: DotShape = .square, ink: DotInk = .plain, days: Int = 7) {
        self.data = data; self.today = today; self.shape = shape; self.ink = ink; self.days = days
    }
    public var body: some View {
        GeometryReader { geo in
            let cell: CGFloat = min(geo.size.width / (CGFloat(days) * 1.2 - 0.2), geo.size.height)
            let g = Self.row(data: data, today: today, days: days, step: cell * 1.2, size: cell * shape.grow)
            ZStack(alignment: .topLeading) {
                InkedCells(cells: g.empty, corner: shape.radius, level: 0, ink: ink, faint: emptyAlpha)
                InkedCells(cells: g.partial, corner: shape.radius, level: 0.5, ink: ink, faint: emptyAlpha)
                InkedCells(cells: g.done, corner: shape.radius, level: 1, ink: ink, faint: emptyAlpha)
            }
        }
    }

    /// Cells laid out by day index along one row, the same step as the wall.
    static func row(data: [Day: Double], today: Day, days: Int, step: CGFloat, size: CGFloat) -> (empty: [CGRect], partial: [CGRect], done: [CGRect]) {
        var empty: [CGRect] = [], partial: [CGRect] = [], done: [CGRect] = []
        let from = today - (days - 1)
        for i in 0..<days {
            let r = CGRect(x: CGFloat(i) * step, y: 0, width: size, height: size)
            let v = data[from + i] ?? 0
            if v >= 1 { done.append(r) } else if v > 0 { partial.append(r) } else { empty.append(r) }
        }
        return (empty, partial, done)
    }
}

/// One bar per week, as tall as that week's done days out of 7; the current week last. No dots at all.
public struct WidgetBars: View {
    public let data: [Day: Double]
    public let today: Day
    public var weeks = 12
    public init(data: [Day: Double], today: Day, weeks: Int = 12) { self.data = data; self.today = today; self.weeks = weeks }
    public var body: some View {
        GeometryReader { geo in
            let gap = geo.size.width / CGFloat(weeks) * 0.25
            let bar = (geo.size.width - gap * CGFloat(weeks - 1)) / CGFloat(weeks)
            let monday = today.weekStart
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(0..<weeks, id: \.self) { w in
                    let start = monday - 7 * (weeks - 1 - w)
                    let done = (0..<7).filter { (data[start + $0] ?? 0) >= 1 }.count
                    let h = max(geo.size.height * CGFloat(done) / 7, geo.size.height * 0.08)
                    let strong = w == weeks - 1 || done >= 5
                    UnevenRoundedRectangle(topLeadingRadius: bar * 0.25, topTrailingRadius: bar * 0.25)
                        .fill(.primary.opacity(strong ? 1 : 0.45))
                        .frame(width: bar, height: h)
                        .widgetAccentableIfAvailable()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
    }
}

/// The check as shapes: an open rounded box (filling from the bottom for count habits), or a solid
/// squircle with the tick cut out in the background color.
public struct WidgetCheck: View {
    public let done: Bool
    public var partial: Double = 0
    /// The color the tick is drawn in (the widget's background).
    public var tick: Color
    public init(done: Bool, partial: Double = 0, tick: Color) { self.done = done; self.partial = partial; self.tick = tick }

    public var body: some View {
        GeometryReader { geo in
            let px = min(geo.size.width, geo.size.height)
            let half = px / 2 * 0.86
            let border = px * 0.06
            ZStack {
                if done {
                    RoundedRectangle(cornerRadius: px * 0.34, style: .continuous).fill(.primary)
                        .frame(width: 2 * half, height: 2 * half)
                        .widgetAccentableIfAvailable()
                    TickShape().stroke(tick, style: StrokeStyle(lineWidth: px * 0.085, lineCap: .round, lineJoin: .round))
                        .frame(width: px, height: px)
                } else {
                    let box = RoundedRectangle(cornerRadius: px * 0.2, style: .continuous)
                    if partial > 0 {
                        Rectangle().fill(.primary.opacity(0.35))
                            .frame(height: 2 * (half - border) * min(partial, 1))
                            .frame(width: 2 * (half - border), height: 2 * (half - border), alignment: .bottom)
                            .clipShape(RoundedRectangle(cornerRadius: px * 0.2 - border / 2, style: .continuous))
                    }
                    box.strokeBorder(.primary.opacity(0.55), lineWidth: border)
                        .frame(width: 2 * half, height: 2 * half)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The tick of the check, in the unit square (same points as `drawCheck`).
public struct TickShape: Shape {
    public init() {}
    public func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.3, y: r.minY + r.height * 0.52))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.44, y: r.minY + r.height * 0.65))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.71, y: r.minY + r.height * 0.37))
        return p
    }
}

extension View {
    /// Marks the solid parts for the tinted / clear home screen (iOS 18+), where they take the accent.
    @ViewBuilder func widgetAccentableIfAvailable() -> some View {
        #if os(iOS)
        self.widgetAccentable()
        #else
        self
        #endif
    }
}
