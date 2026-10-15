import SwiftUI

/*
 * The Notion-style square check, drawn the same in the app and in widgets. A port of Android's
 * Check.kt `drawCheck`: same curves, same proportions, so both platforms animate alike.
 */

public func easeOut(_ t: Double) -> Double { 1 - pow(1 - t, 3) }

/// Overshoots a little past 1 and settles: the "pop" of a completed check.
public func easeOutBack(_ t: Double) -> Double {
    let c = 1.9
    return 1 + (c + 1) * pow(t - 1, 3) + c * pow(t - 1, 2)
}

public extension GraphicsContext {
    /// Check at animation step `t` (0 = open, 1 = done) inside `rect`: a thin rounded box; when done,
    /// a solid fill grows from the center with a small overshoot and the tick draws itself in the
    /// background color. `partial` (0...1) fills the open box from the bottom for habits done several
    /// times a day.
    func drawCheck(in rect: CGRect, t: Double, color: Color, partial: Double = 0, isDark: Bool = false) {
        let px = min(rect.width, rect.height)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let half = px / 2 * 0.86 // room for the overshoot
        // Shape morph: an open box is a rounded square, a done one softens into a squircle.
        let radius = px * (0.2 + 0.14 * t)
        let border = px * 0.06
        let boxRect = CGRect(x: c.x - half + border / 2, y: c.y - half + border / 2, width: 2 * half - border, height: 2 * half - border)
        stroke(Path(roundedRect: boxRect, cornerRadius: radius, style: .continuous),
               with: .color(color.opacity(0.45 * (1 - t) + 0.1)), lineWidth: border)
        if partial > 0, t < 1 {
            // Flush with the stroke's inner edge.
            let inner = half - border + 0.5
            let corner = radius - border / 2 + 0.5
            let box = Path(roundedRect: CGRect(x: c.x - inner, y: c.y - inner, width: 2 * inner, height: 2 * inner), cornerRadius: corner, style: .continuous)
            var clipped = self
            clipped.clip(to: box)
            let top = c.y + inner - 2 * inner * min(partial, 1)
            clipped.fill(Path(CGRect(x: c.x - inner, y: top, width: 2 * inner, height: c.y + inner - top)), with: .color(color.opacity(0.35 * (1 - t))))
        }
        if t > 0 {
            let grow = min(max(easeOutBack(min(t / 0.6, 1)), 0), 1.08)
            let h = half * grow
            fill(Path(roundedRect: CGRect(x: c.x - h, y: c.y - h, width: 2 * h, height: 2 * h), cornerRadius: radius * grow, style: .continuous), with: .color(color))
        }
        let draw = min(max((t - 0.35) / 0.65, 0), 1)
        if draw > 0 {
            let o = CGPoint(x: c.x - px / 2, y: c.y - px / 2)
            var tick = Path()
            tick.move(to: CGPoint(x: o.x + px * 0.3, y: o.y + px * 0.52))
            tick.addLine(to: CGPoint(x: o.x + px * 0.44, y: o.y + px * 0.65))
            tick.addLine(to: CGPoint(x: o.x + px * 0.71, y: o.y + px * 0.37))
            let part = tick.trimmedPath(from: 0, to: easeOut(draw))
            stroke(part, with: .color(isDark ? .white : .black).inverted(isDark: isDark),
                   style: StrokeStyle(lineWidth: px * 0.085, lineCap: .round, lineJoin: .round))
        }
    }
}

private extension GraphicsContext.Shading {
    /// The tick is drawn in the background color: black on a light ink, white on a dark one.
    func inverted(isDark: Bool) -> GraphicsContext.Shading { .color(isDark ? .black : .white) }
}

/// The check drawing at step `t`, as an animatable view: `withAnimation` on `t` or `partial` plays
/// every frame in between (a bare Canvas would jump straight to the end).
public struct CheckGlyph: View, Animatable {
    public var t: Double
    public var partial: Double
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    public init(t: Double, partial: Double = 0) { self.t = t; self.partial = partial }
    nonisolated public var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(t, partial) }
        set { t = newValue.first; partial = newValue.second }
    }
    public var body: some View {
        Canvas { ctx, sz in
            ctx.drawCheck(in: CGRect(origin: .zero, size: sz), t: t, color: palette.ink, partial: partial, isDark: scheme == .dark)
        }
    }
}

/// Animated check: pops and draws its tick when done, squishes on press.
/// `count` of `target` fills the box part way for habits done several times a day.
public struct CheckButton: View {
    public let done: Bool
    public let count: Int
    public let target: Int
    public let size: CGFloat
    public let onTap: () -> Void
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @State private var t: Double
    @State private var partial: Double
    @State private var press = 1.0
    @State private var taps = 0

    public init(done: Bool, count: Int = 0, target: Int = 1, size: CGFloat = 44, onTap: @escaping () -> Void) {
        self.done = done; self.count = count; self.target = target; self.size = size; self.onTap = onTap
        _t = State(initialValue: done ? 1 : 0)
        _partial = State(initialValue: done ? 0 : Double(count) / Double(max(target, 1)))
    }

    public var body: some View {
        let completes = !done && count + 1 >= target
        CheckGlyph(t: t, partial: partial)
        .frame(width: size, height: size)
        .scaleEffect(press)
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .onChange(of: done) { _, now in
            withAnimation(.linear(duration: now ? 0.48 : 0.32)) { t = now ? 1 : 0 }
        }
        .onChange(of: count) { _, now in
            withAnimation(.easeInOut(duration: 0.28)) { partial = done ? 0 : Double(now) / Double(max(target, 1)) }
        }
        .onChange(of: taps) { _, _ in
            // 0.8 in 70 ms, 1.18 in 110 ms when completing, then a loose spring back to 1.
            withAnimation(.linear(duration: 0.07)) { press = 0.8 }
            let back = completes ? 0.18 : 0.07
            if completes { withAnimation(.linear(duration: 0.11).delay(0.07)) { press = 1.18 } }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.35).delay(back)) { press = 1 }
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(spoken)
        .accessibilityAction { tap() }
    }

    private var spoken: String { done ? "Done" : target > 1 ? "\(count) of \(target)" : "Not done" }

    private func tap() {
        taps += 1
        if !done && count + 1 >= target { Haptics.done() } else if done { Haptics.undo() } else { Haptics.tick() }
        onTap()
    }
}
