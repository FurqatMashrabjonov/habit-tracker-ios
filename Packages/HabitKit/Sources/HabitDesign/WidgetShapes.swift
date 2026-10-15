import SwiftUI
import HabitDomain
#if os(iOS)
import WidgetKit
#endif

/*
 * Widgets can't run a Canvas (their views are archived and drawn later), so the check and the dots
 * come again as plain shapes, with the same proportions as `drawCheck` and `drawCell`.
 */

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
    /// Days that are neither due nor done, drawn fainter than empty ones.
    public var off: (Day) -> Bool = { _ in false }
    public init(data: [Day: Double], today: Day, shape: DotShape = .square, maxCell: CGFloat = 16, off: @escaping (Day) -> Bool = { _ in false }) {
        self.data = data; self.today = today; self.shape = shape; self.maxCell = maxCell; self.off = off
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
                CellsShape(cells: groups.empty, corner: shape.radius).fill(.primary.opacity(emptyAlpha))
                CellsShape(cells: groups.partial, corner: shape.radius).fill(.primary.opacity(0.45))
                CellsShape(cells: groups.done, corner: shape.radius).fill(.primary).widgetAccentableIfAvailable()
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

/// The last seven days as one row of big dots.
public struct WidgetWeek: View {
    public let data: [Day: Double]
    public let today: Day
    public var shape: DotShape = .square
    public init(data: [Day: Double], today: Day, shape: DotShape = .square) { self.data = data; self.today = today; self.shape = shape }
    public var body: some View {
        GeometryReader { geo in
            let cell = min(geo.size.width / (7 * 1.2 - 0.2), geo.size.height)
            let g = WidgetDots.cells(data: data, from: today - 6, today: today, step: cell * 1.2, size: cell * shape.grow, off: { _ in false })
            // Seven days from a Monday-less start land in one column; turn it into a row.
            let row = { (rs: [CGRect]) in rs.map { CGRect(x: $0.minY, y: 0, width: $0.width, height: $0.height) } }
            ZStack(alignment: .topLeading) {
                CellsShape(cells: row(g.empty), corner: shape.radius).fill(.primary.opacity(emptyAlpha))
                CellsShape(cells: row(g.partial), corner: shape.radius).fill(.primary.opacity(0.45))
                CellsShape(cells: row(g.done), corner: shape.radius).fill(.primary).widgetAccentableIfAvailable()
            }
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
