import SwiftUI
import HabitDomain

/*
 * The history drawings behind the habit cards' other looks: a chain of the last thirty days and
 * this month as a small calendar. The dot wall and the week strip live in Heatmap.swift.
 */

/// Thirty days as one chain, Seinfeld's "don't break the chain" with the app's own rule drawn in:
/// a done day is a tall link, a missed day a short faint one, a rest day a tall faint one. One short
/// link reads as a bend; two in a row, as a break.
public struct ChainStrip: View, Animatable {
    public let data: [Day: Double]
    public let today: Day
    public var todayValue: Double? = nil
    public var days = 30
    @Environment(\.palette) private var palette
    public init(data: [Day: Double], today: Day, todayValue: Double? = nil, days: Int = 30) {
        self.data = data; self.today = today; self.todayValue = todayValue; self.days = days
    }
    nonisolated public var animatableData: Double {
        get { todayValue ?? 0 }
        set { if todayValue != nil { todayValue = newValue } }
    }
    public var body: some View {
        Canvas { ctx, size in
            let gap: CGFloat = 2
            let w = (size.width - gap * CGFloat(days - 1)) / CGFloat(days)
            let tall = size.height, short = size.height * 0.4
            for i in 0..<days {
                let date = today - (days - 1 - i)
                let v = (todayValue != nil && date == today) ? todayValue! : (data[date] ?? 0)
                let x = CGFloat(i) * (w + gap)
                let h = v >= 1 || v < 0 ? tall : short
                let rect = CGRect(x: x, y: (tall - h) / 2, width: w, height: h)
                let path = Path(roundedRect: rect, cornerRadius: min(w, h) * 0.3, style: .continuous)
                let color = v >= 1 ? palette.ink : v < 0 ? palette.ink.opacity(0.3) : v > 0 ? palette.ink.opacity(partialOpacity(v)) : palette.ink.opacity(emptyAlpha)
                ctx.fill(path, with: .color(color))
                if date == today, v < 1 {
                    ctx.stroke(Path(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), cornerRadius: min(w, h) * 0.3, style: .continuous), with: .color(palette.ink), lineWidth: 1.5)
                }
            }
        }
        .frame(height: 22)
    }
}

/// This month, day by day: done days filled, a rest day dashed, today ringed, the rest of the
/// month faint. Read-only: the card opens the habit, whose calendar can be tapped.
public struct MonthMini: View {
    public let data: [Day: Double]
    public let today: Day
    public var todayValue: Double? = nil
    @Environment(\.palette) private var palette
    public init(data: [Day: Double], today: Day, todayValue: Double? = nil) { self.data = data; self.today = today; self.todayValue = todayValue }

    public var body: some View {
        let first = today.withDay(1)
        let lead = first.weekday - 1
        let length = first.lengthOfMonth
        let weeks = (lead + length + 6) / 7
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(Words.weekdaysShort, id: \.self) {
                    Text($0).font(.system(size: 9.5, weight: .medium, design: .monospaced)).foregroundStyle(palette.dim).frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<weeks, id: \.self) { week in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { col in
                        let n = week * 7 + col - lead + 1
                        if n >= 1 && n <= length { cell(first.withDay(n), n) } else { Color.clear.aspectRatio(1, contentMode: .fit) }
                    }
                }
            }
        }
    }

    private func cell(_ date: Day, _ n: Int) -> some View {
        let v = (todayValue != nil && date == today) ? todayValue! : (data[date] ?? 0)
        let future = date > today
        let done = v >= 1
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return ZStack {
            if future {
                shape.stroke(palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            } else {
                shape.fill(done ? palette.ink : v < 0 ? palette.tile : v > 0 ? palette.ink.opacity(partialOpacity(v)) : palette.ink.opacity(emptyAlpha))
            }
            if date == today && !done { shape.stroke(palette.ink, lineWidth: 1.5).padding(0.75) }
            Text("\(n)").font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(done ? palette.onInk : future ? palette.dim.opacity(0.6) : palette.dim)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
