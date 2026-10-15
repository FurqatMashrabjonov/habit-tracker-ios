import SwiftUI

/*
 * One small black-and-white burst when a habit gets done: a dozen little day dots scatter in a
 * circle, spin, and fade. A port of Android's Confetti.kt; drawn over the whole screen so a card
 * doesn't clip it.
 */

public struct Burst: Identifiable, Sendable {
    public let id = UUID()
    public let origin: CGPoint
    public let seed: UInt64
    public let start: Date
    public static let duration: TimeInterval = 0.78
}

/// Fire bursts from anywhere below a `ConfettiHost`.
@Observable
public final class Confetti: @unchecked Sendable {
    public var bursts: [Burst] = []
    public var reduceMotion = false
    public init() {}

    /// `origin` in the host's coordinate space (use `.global` and a host filling the window).
    public func fire(at origin: CGPoint) {
        guard !reduceMotion else { return }
        bursts.append(Burst(origin: origin, seed: UInt64.random(in: 0...UInt64.max), start: Date()))
    }
}

public struct ConfettiHost<Content: View>: View {
    @State private var confetti = Confetti()
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        ZStack {
            content.environment(confetti)
            if !confetti.bursts.isEmpty {
                TimelineView(.animation) { timeline in
                    Canvas { ctx, _ in
                        for b in confetti.bursts {
                            let t = min(timeline.date.timeIntervalSince(b.start) / Burst.duration, 1)
                            ctx.drawBurst(b, t: t, ink: palette.ink, gray: palette.dim)
                        }
                    }
                    .onChange(of: timeline.date) { _, now in
                        confetti.bursts.removeAll { now.timeIntervalSince($0.start) >= Burst.duration }
                    }
                }
                .allowsHitTesting(false)
                .ignoresSafeArea()
            }
        }
        .onAppear { confetti.reduceMotion = reduceMotion }
        .onChange(of: reduceMotion) { _, v in confetti.reduceMotion = v }
    }
}

private func easeOutCubic(_ t: Double) -> Double { 1 - pow(1 - t, 3) }

/// Deterministic per burst, like Kotlin's `Random(seed)`: the dots don't jitter between frames.
private struct Rng {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

extension GraphicsContext {
    func drawBurst(_ burst: Burst, t: Double, ink: Color, gray: Color) {
        var rnd = Rng(state: burst.seed)
        let o = burst.origin
        let n = 12
        let move = easeOutCubic(min(t / 0.7, 1))
        let life = 1 - min(max((t - 0.35) / 0.65, 0), 1)
        for i in 0..<n {
            let angle = (Double(i) * 360 / Double(n) + (rnd.next() - 0.5) * 18) * .pi / 180
            let reach = 52 + rnd.next() * 40
            let size = (6 + rnd.next() * 4) * life
            let spin = (rnd.next() - 0.5) * 540 * t
            let x = o.x + cos(angle) * reach * move
            let y = o.y + sin(angle) * reach * move + 18 * t * t // a touch of gravity
            guard size > 0.3 else { continue }
            var c = self
            c.translateBy(x: x, y: y)
            c.rotate(by: .degrees(spin))
            c.fill(Path(roundedRect: CGRect(x: -size / 2, y: -size / 2, width: size, height: size), cornerRadius: size * 0.3),
                   with: .color((i % 3 == 0 ? gray : ink).opacity(life)))
        }
    }
}

/// Circular progress ring. Completed (>= 1) becomes a solid disc when `solidWhenDone`.
public struct ProgressRing<Content: View>: View {
    public let progress: Double
    public var size: CGFloat = 36
    public var stroke: CGFloat = 3
    public var solidWhenDone = false
    @ViewBuilder public let content: (Bool) -> Content
    @Environment(\.palette) private var palette

    public init(progress: Double, size: CGFloat = 36, stroke: CGFloat = 3, solidWhenDone: Bool = false, @ViewBuilder content: @escaping (Bool) -> Content) {
        self.progress = progress; self.size = size; self.stroke = stroke; self.solidWhenDone = solidWhenDone; self.content = content
    }

    public var body: some View {
        let solid = solidWhenDone && progress >= 1
        ZStack {
            if solid {
                Circle().fill(palette.ink)
            } else {
                Circle().stroke(palette.tint, lineWidth: stroke)
                Circle().trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(palette.ink, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.default, value: progress)
            }
            content(solid)
        }
        .frame(width: size, height: size)
    }
}
