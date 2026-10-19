import SwiftUI
import HabitData
import HabitDesign
import HabitDomain

/// The paywall, as on Android: what Pro adds, each shown rather than listed; yearly (with its free
/// trial) or lifetime, anchored against each other; and restore.
struct Paywall: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var store = Store.shared
    @State private var choice = Store.yearly
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        let trial = store.trialDays
        let ready = store.products[choice] != nil
        // Scrolls when large text doesn't fit, so the billing terms are never cut off.
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            // The user's own wall fills in, dot by dot, with the count of its days: what Pro keeps growing.
            WallHero()
            Text("Keep the wall growing.").font(Type.headlineSmall)
            Text("Four habits are free, forever. Pro adds:").font(Type.bodyMedium).foregroundStyle(palette.dim)
            // What you get, each alive: a wall that keeps filling, a nudge that drops in, a widget changing its look, two phones in step.
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    FeatureTile(title: "Unlimited habits", note: "As many walls as you like") { MiniWall() }
                    FeatureTile(title: "Evening check-in", note: "A nudge only when today is still open") { MiniNudge() }
                }
                GridRow {
                    FeatureTile(title: "Home screen looks", note: "Widget looks, dot shapes and app icons") { MiniLooks() }
                    FeatureTile(title: "Sync", note: "The same dots on every phone") { MiniSync() }
                }
            }
            HStack(spacing: 10) {
                plan(Store.yearly, "Yearly", store.price(Store.yearly) ?? "$7.99",
                     trial.map { "\($0) days free" }, (store.monthlyOfYearly ?? "$0.67") + " / month")
                plan(Store.lifetime, "Lifetime", store.price(Store.lifetime) ?? "$19.99",
                     "Pay once", "Pays off in \(Self.years(store.lifetimeInYears ?? 2.5)) years, then it's yours")
            }
            .fixedSize(horizontal: false, vertical: true)
            Button {
                busy = true
                _Concurrency.Task {
                    switch await store.buy(choice) {
                    case .bought: dismiss()
                    case .pending: message = "Waiting for approval"
                    case .failed: message = "Not available yet"
                    case .cancelled: break
                    }
                    busy = false
                }
            } label: {
                ZStack {
                    if busy { ProgressView().tint(palette.onInk) } else {
                        Text(!ready ? "Not available yet" : choice == Store.yearly && trial != nil ? "Start free trial" : "Get Pro").font(Type.titleSmall)
                    }
                }
                .foregroundStyle(ready ? palette.onInk : palette.dim)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(ready ? palette.ink : palette.tileHigh, in: Capsule())
            }
            .disabled(!ready || busy)
            .buttonStyle(Bouncy(scale: 0.97))
            Text(choice == Store.lifetime ? "One payment, yours for good."
                 : trial != nil ? "Billed yearly after the trial. Cancel anytime in Settings › Apple Account › Subscriptions."
                 : "Billed yearly. Cancel anytime in Settings › Apple Account › Subscriptions.")
                .font(Type.bodySmall).foregroundStyle(palette.dim).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            HStack(spacing: 18) {
                Button("Restore purchase") {
                    _Concurrency.Task { message = await store.restore() ? "Pro restored" : "No purchase found for this Apple Account" }
                }
                Link("Terms", destination: URL(string: "https://habitdots-app.web.app/terms")!)
                Link("Privacy", destination: URL(string: "https://habitdots-app.web.app/privacy")!)
            }
            .font(Type.labelLarge).foregroundStyle(palette.ink).frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(700), .large])
        .textCap()
        .presentationCornerRadius(Radius.sheet)
        .presentationBackground(palette.surfaceLow)
        .overlay(alignment: .bottom) {
            if let message { Toast(text: message).task { try? await _Concurrency.Task.sleep(for: .seconds(2)); self.message = nil } }
        }
        .animation(.snappy, value: message)
    }

    /// "2.5" or "3", whichever reads naturally.
    private static func years(_ y: Double) -> String {
        let r = (y * 2).rounded() / 2
        return r == r.rounded() ? "\(Int(r))" : String(format: "%.1f", r)
    }

    private func plan(_ id: String, _ title: String, _ price: String, _ note: String?, _ anchor: String) -> some View {
        let selected = choice == id
        return Button { choice = id } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(Type.labelLarge).foregroundStyle(palette.dim)
                    Spacer()
                    ZStack {
                        Circle().fill(selected ? palette.ink : .clear)
                        Circle().stroke(selected ? .clear : palette.outline, lineWidth: 1.5)
                        if selected { Image("Icons/ui-check").resizable().frame(width: 12, height: 12).foregroundStyle(palette.onInk) }
                    }
                    .frame(width: 20, height: 20)
                }
                // Long local prices shrink to fit one line instead of wrapping.
                Text(price).font(Type.titleLarge).lineLimit(1).minimumScaleFactor(0.5)
                if let note { Text(note).font(Type.labelMedium).foregroundStyle(palette.ink) }
                Text(anchor).font(Type.labelSmall).foregroundStyle(palette.dim).lineLimit(3).padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
            .background(palette.surfaceLow, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .stroke(selected ? palette.ink : palette.hairline, lineWidth: selected ? 2 : 1))
            .animation(.easeOut(duration: 0.2), value: selected)
        }
        .buttonStyle(.plain)
    }
}

/// A Pro feature: its picture on a quiet tile, then a title and a line about it.
private struct FeatureTile<Picture: View>: View {
    let title: String
    let note: String
    @ViewBuilder let picture: Picture
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            picture
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(palette.tile, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            Text(title).font(Type.labelLarge)
            Text(note).font(Type.labelSmall).foregroundStyle(palette.dim).lineLimit(2, reservesSpace: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(palette.background, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).stroke(palette.softBorder, lineWidth: 1))
    }
}

/// A clock from 0 to 1 over `period` seconds with a rest at the end, driven by the frame clock.
private func phase(_ date: Date, period: Double, rest: Double = 1.2) -> Double {
    min(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period + rest) / period, 1)
}

/// The hero: the first habit's last weeks as a wall that fills in chronologically, and how many days are
/// on it. A phone with no history gets a sample wall, so the page still shows what it is about.
private struct WallHero: View {
    // The sheet is presented above where the model is injected, so it is read directly.
    private let model = AppModel.shared
    @Environment(\.palette) private var palette
    @State private var t = 0.0
    private let weeks = 18
    var body: some View {
        let today = model.today
        let from = today.weekStart - 7 * (weeks - 1)
        let real = (model.rows?.first?.progress ?? [:]).filter { $0.key >= from && $0.key <= today && $0.value >= 1 }.keys.sorted()
        let done: [Day] = real.count >= 5 ? real : (0...(today - from)).map { from + $0 }.enumerated().filter { ($0.offset * 2654435761) % 100 < 72 }.map(\.element)
        let shown = min(Int(t * Double(done.count)), done.count)
        HStack(spacing: 14) {
            Canvas { ctx, size in
                let cell = size.width / (CGFloat(weeks) * 1.2 - 0.2)
                let data = Dictionary(uniqueKeysWithValues: done.prefix(shown).map { ($0, 1.0) })
                ctx.drawHeatmap(data, color: palette.ink, from: from, last: today, cell: cell)
            }
            .frame(height: 48 * 8.2 / 7)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(shown)").font(Type.displaySmall).contentTransition(.numericText())
                Text("days").font(Type.labelSmall).foregroundStyle(palette.dim)
            }
        }
        .onAppear { t = 0; withAnimation(.easeOut(duration: 1.8)) { t = 1 } }
    }
}

/// A small wall that keeps filling in, one dot at a time.
private struct MiniWall: View {
    @Environment(\.palette) private var palette
    private let rows = ["1101111011", "1110111101", "0111011111"]
    var body: some View {
        TimelineView(.animation) { tl in
            let t = phase(tl.date, period: 2.6)
            let total = rows.reduce(0) { $0 + $1.filter { $0 == "1" }.count }
            var k = 0
            VStack(spacing: 3) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, c in
                            let on = c == "1" && { defer { k += 1 }; return Double(k) < t * Double(total) }()
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(on ? palette.ink : palette.tint).frame(width: 9, height: 9)
                        }
                    }
                }
            }
        }
    }
}

/// The evening check-in as the notification it is, dropping in and leaving again.
private struct MiniNudge: View {
    @Environment(\.palette) private var palette
    var body: some View {
        TimelineView(.animation) { tl in
            let t = phase(tl.date, period: 2.4, rest: 0.6)
            let k = t < 0.2 ? t / 0.2 : t > 0.8 ? (1 - t) / 0.2 : 1
            let e = 1 - pow(1 - k, 3)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(palette.ink).frame(width: 12, height: 12)
                Text("2 still open").font(Type.labelSmall.weight(.semibold))
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(palette.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(palette.softBorder, lineWidth: 1))
            .offset(y: -40 * (1 - e)).opacity(e)
        }
    }
}

/// One tiny widget that changes its look every two seconds: Paper, Dot matrix, Outline, Receipt, E-ink.
private struct MiniLooks: View {
    private struct L { let bg: Color; let ink: Color; let off: Color; var round = false; var outline = false; var glow = false; var sharp = false }
    private let looks = [
        L(bg: .white, ink: Color(hex: 0x1F1E1B), off: Color(hex: 0xE6E5E1)),
        L(bg: .black, ink: .white, off: Color(hex: 0x2A2A2D), round: true, glow: true),
        L(bg: .white, ink: Color(hex: 0x1F1E1B), off: .clear, round: true, outline: true),
        L(bg: Color(hex: 0xF4F4F2), ink: Color(hex: 0x262626), off: Color(hex: 0xDCDCD8), sharp: true),
        L(bg: Color(hex: 0xECECEA), ink: Color(hex: 0x2B2B2B), off: Color(hex: 0xCFCFCC)),
    ]
    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { tl in
            let i = Int(tl.date.timeIntervalSinceReferenceDate / 2) % looks.count
            ZStack {
                ForEach(Array(looks.enumerated()), id: \.offset) { k, l in
                    widget(l).opacity(k == i ? 1 : 0).scaleEffect(k == i ? 1 : 0.94)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: i)
        }
    }
    private func widget(_ l: L) -> some View {
        let shape = RoundedRectangle(cornerRadius: l.sharp ? 3 : 8, style: .continuous)
        return VStack(alignment: .leading, spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(l.ink).frame(width: 24, height: 4)
            HStack(spacing: 2) {
                ForEach(0..<7, id: \.self) { d in
                    let on = d % 3 != 1
                    let dot = RoundedRectangle(cornerRadius: l.round ? 2.5 : l.sharp ? 0 : 1.2, style: .continuous)
                    ZStack {
                        if l.outline && !on { dot.stroke(l.ink.opacity(0.45), lineWidth: 1) } else { dot.fill(on ? l.ink : l.off) }
                        if l.glow && on { dot.stroke(l.ink.opacity(0.35), lineWidth: 2) }
                    }
                    .frame(width: 5, height: 5)
                }
            }
        }
        .padding(6).frame(width: 62, height: 40, alignment: .topLeading)
        .background(l.bg, in: shape)
        .overlay { if l.outline { shape.stroke(l.ink, lineWidth: 1) } }
    }
}

/// Two phones whose dots appear in step: the same wall on both.
private struct MiniSync: View {
    @Environment(\.palette) private var palette
    var body: some View {
        TimelineView(.animation) { tl in
            let t = phase(tl.date, period: 2.4, rest: 0.9)
            HStack(spacing: 8) {
                phone(t)
                Image("Icons/ui-cloud").resizable().frame(width: 22, height: 22).opacity(0.45 + 0.55 * sin(t * .pi))
                phone(t)
            }
        }
    }
    private func phone(_ t: Double) -> some View {
        VStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { r in
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { c in
                        let i = r * 3 + c
                        let on = (i * 7) % 5 != 2 && Double(i) < t * 9
                        RoundedRectangle(cornerRadius: 1).fill(on ? palette.ink : palette.ink.opacity(0.15)).frame(width: 3, height: 3)
                    }
                }
            }
        }
        .padding(.horizontal, 4).padding(.vertical, 5)
        .frame(width: 22, height: 32, alignment: .top)
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(palette.ink, lineWidth: 1.5))
    }
}

