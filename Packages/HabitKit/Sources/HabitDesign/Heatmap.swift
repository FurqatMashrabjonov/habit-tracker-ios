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
    /// A thin ring around a cell: marks today so the eye finds "now" in a wall of history.
    func outlineCell(at origin: CGPoint, cell: CGFloat, color: Color, shape: DotShape = .square) {
        let s = cell * shape.grow
        let rect = CGRect(origin: origin, size: CGSize(width: s, height: s)).insetBy(dx: 0.75, dy: 0.75)
        stroke(Path(roundedRect: rect, cornerRadius: s * shape.radius, style: .continuous), with: .color(color), lineWidth: 1.5)
    }

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
                     shape: DotShape = .square, todayValue: Double? = nil, today: Day? = nil, markToday: Bool = false) {
        let origin = grid ? from.weekStart : from
        let step = cell * 1.2
        var date = from
        while date <= last {
            let i = date - origin
            let (c, r) = grid ? (i / 7, i % 7) : (i, 0)
            let value = (todayValue != nil && date == today) ? todayValue! : (data[date] ?? 0)
            let at = CGPoint(x: CGFloat(c) * step, y: CGFloat(r) * step)
            drawCell(at: at, cell: cell, progress: value, color: color, shape: shape)
            if markToday, date == today, value < 1 { outlineCell(at: at, cell: cell, color: color, shape: shape) }
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
    /// Faint month names over the first week of each month, and a ring on today's cell.
    public var labels = false
    /// Today's dot pops (small, over, settle) the moment this turns true: a check landing on the wall.
    public var popToday = false
    @Environment(\.palette) private var palette
    @State private var pop: CGFloat = 1

    public init(data: [Day: Double], today: Day, targetCell: CGFloat = 11, todayValue: Double? = nil, labels: Bool = false, popToday: Bool = false, onTap: ((Day) -> Void)? = nil) {
        self.data = data; self.today = today; self.targetCell = targetCell; self.todayValue = todayValue; self.labels = labels; self.popToday = popToday; self.onTap = onTap
    }

    private var top: CGFloat { labels ? 14 : 0 }

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
        let top = top
        HeightFromWidth(height: { Self.geometry(width: $0, target: targetCell).cell * 8.2 + top }) {
            GeometryReader { geo in
                let (weeks, cell) = Self.geometry(width: geo.size.width, target: targetCell)
                let start = today.weekStart - 7 * (weeks - 1)
                let step = cell * 1.2
                Canvas { ctx, _ in
                    if labels {
                        // A month label over the first week whose Monday is in a new month (not the cut-off first column).
                        let font = Font.system(size: 9.5, weight: .medium, design: .monospaced)
                        for w in 1..<max(weeks, 1) {
                            let monday = start + 7 * w
                            if monday.month != (monday - 7).month {
                                ctx.draw(Text(Words.months[monday.month - 1].prefix(3)).font(font).foregroundStyle(palette.dim),
                                         at: CGPoint(x: step * CGFloat(w), y: 5), anchor: .leading)
                            }
                        }
                    }
                    var body = ctx
                    body.translateBy(x: 0, y: top)
                    body.drawHeatmap(data, color: palette.ink, from: start, last: today, cell: cell, todayValue: todayValue, today: today, markToday: labels)
                    if pop != 1 {
                        // Draw today's cell again, scaled about its centre, over the wall.
                        let i = today - start, s = cell
                        let c = CGPoint(x: CGFloat(i / 7) * step + s / 2, y: CGFloat(i % 7) * step + s / 2)
                        var over = ctx
                        over.translateBy(x: c.x, y: c.y + top); over.scaleBy(x: pop, y: pop); over.translateBy(x: -s / 2, y: -s / 2)
                        over.drawCell(at: .zero, cell: s, progress: todayValue ?? data[today] ?? 1, color: palette.ink)
                    }
                }
                .onChange(of: popToday) { _, on in
                    guard on else { return }
                    pop = 0.2
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { pop = 1 }
                }
                .contentShape(Rectangle())
                // Without a day handler the wall is inert, so a tap on it reaches the card behind (opens the habit).
                .allowsHitTesting(onTap != nil)
                .onTapGesture { pos in
                    let date = start + Int(pos.x / step) * 7 + Int((pos.y - top) / step)
                    if pos.y >= top, date <= today { onTap?(date) }
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
    /// Weekday letters under the cells and a ring on today's cell.
    public var labels = false
    @Environment(\.palette) private var palette
    public init(data: [Day: Double], today: Day, todayValue: Double? = nil, labels: Bool = false) {
        self.data = data; self.today = today; self.todayValue = todayValue; self.labels = labels
    }
    nonisolated public var animatableData: Double {
        get { todayValue ?? 0 }
        set { if todayValue != nil { todayValue = newValue } }
    }
    private var ratio: CGFloat { 7 * 1.2 - 0.2 }
    public var body: some View {
        HeightFromWidth(height: { w in w / (7 * 1.2 - 0.2) + (labels ? 16 : 0) }) {
            Canvas { ctx, size in
                let cell = size.width / ratio
                let font = Font.system(size: 10, weight: .medium, design: .monospaced)
                for i in 0..<7 {
                    let date = today - (6 - i)
                    let value = (todayValue != nil && date == today) ? todayValue! : (data[date] ?? 0)
                    let at = CGPoint(x: CGFloat(i) * cell * 1.2, y: 0)
                    ctx.drawCell(at: at, cell: cell, progress: value, color: palette.ink)
                    if labels {
                        if date == today, value < 1 { ctx.outlineCell(at: at, cell: cell, color: palette.ink) }
                        ctx.draw(Text(Words.weekdaysShort[date.weekday - 1]).font(font).foregroundStyle(date == today ? palette.ink : palette.dim),
                                 at: CGPoint(x: at.x + cell / 2, y: cell + 9), anchor: .center)
                    }
                }
            }
        }
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
