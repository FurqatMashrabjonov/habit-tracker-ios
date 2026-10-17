import SwiftUI
import HabitDomain

/*
 * Day dots, a port of Android's Heatmap.kt: weeks as columns, Monday on top; empty days a faint
 * tint; partial progress darkens with the count (like the logo) but stays well below a completed
 * day, the only solid cell. The exact count is on the check button and the habit page.
 */

/// How a day's cell is drawn: rounded square (the app's own), circle, or a pixel that touches its neighbours.
public enum DotShape: String, CaseIterable, Sendable {
    case square, round, pixel
    var radius: CGFloat { switch self { case .square: 0.34; case .round: 0.5; case .pixel: 0.04 } }
    var grow: CGFloat { self == .pixel ? 1.12 : 1 }
}

let emptyAlpha = 0.16
let firstAlpha = 0.3
let partialAlpha = 0.55

/// Any progress starts at `firstAlpha` (clearly not empty) and darkens evenly toward `partialAlpha`.
func partialOpacity(_ progress: Double) -> Double { firstAlpha + (partialAlpha - firstAlpha) * min(progress, 1) }

public extension GraphicsContext {
    /// One day as a rounded square at `origin`, `cell` points wide.
    func drawCell(at origin: CGPoint, cell: CGFloat, progress: Double, color: Color, shape: DotShape = .square) {
        let s = cell * shape.grow // a pixel fills the gap to the next cell
        let rect = CGRect(origin: origin, size: CGSize(width: s, height: s))
        let path = Path(roundedRect: rect, cornerRadius: s * shape.radius, style: .continuous)
        if progress >= 1 { fill(path, with: .color(color)); return }
        if progress > 0 { fill(path, with: .color(color.opacity(partialOpacity(progress)))); return }
        fill(path, with: .color(color.opacity(emptyAlpha)))
        if progress < 0 { // a rest day (-1): a short dash, "excused" rather than missed
            let dash = CGRect(x: origin.x + s * 0.25, y: origin.y + s * 0.42, width: s * 0.5, height: s * 0.16)
            fill(Path(roundedRect: dash, cornerRadius: s * 0.08), with: .color(color.opacity(partialAlpha)))
        }
    }

    /// Cells for `from`...`last`, weeks as columns (`grid`) or one row. Step between cells is 1.2 × cell.
    func drawHeatmap(_ data: [Day: Double], color: Color, from: Day, last: Day, cell: CGFloat, grid: Bool = true,
                     shape: DotShape = .square, todayValue: Double? = nil, today: Day? = nil) {
        let origin = grid ? from.weekStart : from
        let step = cell * 1.2
        var date = from
        while date <= last {
            let i = date - origin
            let (c, r) = grid ? (i / 7, i % 7) : (i, 0)
            let value = (todayValue != nil && date == today) ? todayValue! : (data[date] ?? 0)
            drawCell(at: CGPoint(x: CGFloat(c) * step, y: CGFloat(r) * step), cell: cell, progress: value, color: color, shape: shape)
            date = date + 1
        }
    }
}

/// Heatmap grid ending at `today` that shows as many whole weeks as fit the width (habit cards).
public struct FitHeatmap: View, Animatable {
    public let data: [Day: Double]
    public let today: Day
    public var targetCell: CGFloat = 11
    public var todayValue: Double? = nil
    public var onTap: ((Day) -> Void)? = nil
    @Environment(\.palette) private var palette

    public init(data: [Day: Double], today: Day, targetCell: CGFloat = 11, todayValue: Double? = nil, onTap: ((Day) -> Void)? = nil) {
        self.data = data; self.today = today; self.targetCell = targetCell; self.todayValue = todayValue; self.onTap = onTap
    }

    /// Today's cell animates (a check fills it); the rest of the history is static.
    nonisolated public var animatableData: Double {
        get { todayValue ?? 0 }
        set { if todayValue != nil { todayValue = newValue } }
    }

    static func geometry(width: CGFloat, target: CGFloat) -> (weeks: Int, cell: CGFloat) {
        // An unbounded or empty offer (stacks asking for an ideal size): a month of weeks at the target size.
        guard width.isFinite, width > 0 else { return (5, target) }
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
                // Without a day handler the wall is inert, so a tap on it reaches the card behind (opens the habit).
                .allowsHitTesting(onTap != nil)
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
        let w = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 320
        return CGSize(width: w, height: height(w))
    }
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for v in subviews { v.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size)) }
    }
}

/// The last seven days as one row of big cells, filling the width (compact habit cards).
public struct WeekStrip: View, Animatable {
    public let data: [Day: Double]
    public let today: Day
    public var todayValue: Double? = nil
    @Environment(\.palette) private var palette
    public init(data: [Day: Double], today: Day, todayValue: Double? = nil) { self.data = data; self.today = today; self.todayValue = todayValue }
    nonisolated public var animatableData: Double {
        get { todayValue ?? 0 }
        set { if todayValue != nil { todayValue = newValue } }
    }
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

/// `FitHeatmap` with month names above the weeks and Tu/Th/Sa beside the rows, HabitKit-style.
/// Labels use a monospace face so they line up like a chart's axis.
public struct LabeledHeatmap: View {
    public let data: [Day: Double]
    public let today: Day
    public var targetCell: CGFloat = 13
    @Environment(\.palette) private var palette
    public init(data: [Day: Double], today: Day, targetCell: CGFloat = 13) { self.data = data; self.today = today; self.targetCell = targetCell }

    private let side: CGFloat = 24
    private let top: CGFloat = 16

    public var body: some View {
        HeightFromWidth(height: { w in top + FitHeatmap.geometry(width: w - side, target: targetCell).cell * 8.2 }) {
            GeometryReader { geo in
                let (weeks, cell) = FitHeatmap.geometry(width: geo.size.width - side, target: targetCell)
                let step = cell * 1.2
                let start = today.weekStart - 7 * (weeks - 1)
                let label = Font.system(size: 11, weight: .medium, design: .monospaced)
                ZStack(alignment: .topLeading) {
                    // A month label sits over the first week whose Monday falls in a new month.
                    ForEach(1..<max(weeks, 1), id: \.self) { w in
                        let monday = start + 7 * w
                        if monday.month != (monday - 7).month {
                            Text(Words.months[monday.month - 1].prefix(3)).font(label).foregroundStyle(palette.dim)
                                .offset(x: side + step * CGFloat(w))
                        }
                    }
                    ForEach([1, 3, 5], id: \.self) { row in
                        Text(Words.weekdaysShort[row]).font(label).foregroundStyle(palette.dim)
                            .offset(y: top + step * CGFloat(row) + (cell - 13) / 2)
                    }
                    Canvas { ctx, _ in
                        ctx.drawHeatmap(data, color: palette.ink, from: start, last: today, cell: cell)
                    }
                    .offset(x: side, y: top)
                }
            }
        }
    }
}
