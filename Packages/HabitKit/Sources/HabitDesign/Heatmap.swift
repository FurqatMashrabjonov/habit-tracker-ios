import SwiftUI
import HabitDomain

/*
 * Day dots, a port of Android's Heatmap.kt: weeks as columns, Monday on top; empty days a faint
 * tint; partial progress fills the cell from the bottom; a completed day is the only solid cell.
 */

/// How a day's cell is drawn: rounded square (the app's own), circle, or a pixel that touches its neighbours.
public enum DotShape: String, CaseIterable, Sendable {
    case square, round, pixel
    var radius: CGFloat { switch self { case .square: 0.34; case .round: 0.5; case .pixel: 0.04 } }
    var grow: CGFloat { self == .pixel ? 1.12 : 1 }
}

public enum HeatmapStyle: Sendable { case fill, intensity }

let emptyAlpha = 0.16
let partialAlpha = 0.7

/// 0 | 1-24 | 25-49 | 50-74 | 75-99 | 100+ percent.
func intensityAlpha(_ progress: Double) -> Double {
    switch progress {
    case ...0: 0
    case ..<0.25: 0.3
    case ..<0.5: 0.45
    case ..<0.75: 0.6
    case ..<1: 0.75
    default: 1
    }
}

public extension GraphicsContext {
    /// One day as a rounded square at `origin`, `cell` points wide.
    func drawCell(at origin: CGPoint, cell: CGFloat, progress: Double, color: Color, style: HeatmapStyle = .fill, shape: DotShape = .square) {
        let s = cell * shape.grow // a pixel fills the gap to the next cell
        let rect = CGRect(origin: origin, size: CGSize(width: s, height: s))
        let path = Path(roundedRect: rect, cornerRadius: s * shape.radius, style: .continuous)
        if progress >= 1 { fill(path, with: .color(color)); return }
        fill(path, with: .color(color.opacity(emptyAlpha)))
        if progress <= 0 { return }
        if style == .intensity {
            fill(path, with: .color(color.opacity(intensityAlpha(progress))))
        } else {
            var clipped = self
            clipped.clip(to: path)
            let h = s * progress
            clipped.fill(Path(CGRect(x: origin.x, y: origin.y + s - h, width: s, height: h)), with: .color(color.opacity(partialAlpha)))
        }
    }

    /// Cells for `from`...`last`, weeks as columns (`grid`) or one row. Step between cells is 1.2 × cell.
    func drawHeatmap(_ data: [Day: Double], color: Color, from: Day, last: Day, cell: CGFloat, grid: Bool = true,
                     style: HeatmapStyle = .fill, shape: DotShape = .square, todayValue: Double? = nil, today: Day? = nil) {
        let origin = grid ? from.weekStart : from
        let step = cell * 1.2
        var date = from
        while date <= last {
            let i = date - origin
            let (c, r) = grid ? (i / 7, i % 7) : (i, 0)
            let value = (todayValue != nil && date == today) ? todayValue! : (data[date] ?? 0)
            drawCell(at: CGPoint(x: CGFloat(c) * step, y: CGFloat(r) * step), cell: cell, progress: value, color: color, style: style, shape: shape)
            date = date + 1
        }
    }
}

/// Heatmap grid ending at `today` that shows as many whole weeks as fit the width (habit cards).
public struct FitHeatmap: View {
    public let data: [Day: Double]
    public let today: Day
    public var targetCell: CGFloat = 11
    public var todayValue: Double? = nil
    public var onTap: ((Day) -> Void)? = nil
    @Environment(\.palette) private var palette

    public init(data: [Day: Double], today: Day, targetCell: CGFloat = 11, todayValue: Double? = nil, onTap: ((Day) -> Void)? = nil) {
        self.data = data; self.today = today; self.targetCell = targetCell; self.todayValue = todayValue; self.onTap = onTap
    }

    static func geometry(width: CGFloat, target: CGFloat) -> (weeks: Int, cell: CGFloat) {
        let weeks = max(Int((width + target * 0.2) / (target * 1.2)), 1)
        return (weeks, width / (CGFloat(weeks) * 1.2 - 0.2))
    }

    public var body: some View {
        HeightFromWidth(height: { Self.geometry(width: $0, target: targetCell).cell * 8.2 }) {
            GeometryReader { geo in
                let (weeks, cell) = Self.geometry(width: geo.size.width, target: targetCell)
                let start = today.weekStart - 7 * (weeks - 1)
                Canvas { ctx, _ in
                    ctx.drawHeatmap(data, color: palette.ink, from: start, last: today, cell: cell, todayValue: todayValue, today: today)
                }
                .contentShape(Rectangle())
                .onTapGesture { pos in
                    let step = cell * 1.2
                    let date = start + Int(pos.x / step) * 7 + Int(pos.y / step)
                    if date <= today { onTap?(date) }
                }
            }
        }
    }
}

/// Takes the offered width and a height computed from it (the heatmap's whole weeks decide its height).
public struct HeightFromWidth: Layout {
    let height: (CGFloat) -> CGFloat
    public init(height: @escaping (CGFloat) -> CGFloat) { self.height = height }
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 320
        return CGSize(width: w, height: height(w))
    }
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for v in subviews { v.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size)) }
    }
}

/// The last seven days as one row of big cells, filling the width (compact habit cards).
public struct WeekStrip: View {
    public let data: [Day: Double]
    public let today: Day
    public var todayValue: Double? = nil
    @Environment(\.palette) private var palette
    public init(data: [Day: Double], today: Day, todayValue: Double? = nil) { self.data = data; self.today = today; self.todayValue = todayValue }
    public var body: some View {
        Canvas { ctx, size in
            let cell = size.width / (7 * 1.2 - 0.2)
            for i in 0..<7 {
                let date = today - (6 - i)
                let value = (todayValue != nil && date == today) ? todayValue! : (data[date] ?? 0)
                ctx.drawCell(at: CGPoint(x: CGFloat(i) * cell * 1.2, y: 0), cell: cell, progress: value, color: palette.ink)
            }
        }
        .aspectRatio(7 * 1.2 - 0.2, contentMode: .fit)
    }
}
