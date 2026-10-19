import SwiftUI
import HabitDesign

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
            Text("HabitDots Pro").font(Type.headlineSmall)
            Text("Everything you see is free: tracking, every widget, reminders and your data, with up to \(Store.freeHabits) habits. Pro adds:")
                .font(Type.bodyMedium).foregroundStyle(palette.dim)
            // What you get, drawn: a tile per feature with a small picture of it.
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    FeatureTile(title: "Unlimited habits", note: "As many walls as you like") { MiniWall() }
                    FeatureTile(title: "Evening check-in", note: "A nudge only when today is still open") { MiniNudge() }
                }
                GridRow {
                    FeatureTile(title: "Sync", note: "The same dots on every phone") { MiniSync() }
                    FeatureTile(title: "Home screen looks", note: "Widget looks, dot shapes and app icons") { MiniLooks() }
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

/// Three rows of dots, mostly filled: the wall a habit grows into.
private struct MiniWall: View {
    @Environment(\.palette) private var palette
    private let pattern = [
        "1101111011", "1110111101", "0111011111",
    ]
    var body: some View {
        VStack(spacing: 3) {
            ForEach(pattern, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, c in
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(c == "1" ? palette.ink : palette.tint).frame(width: 9, height: 9)
                    }
                }
            }
        }
    }
}

/// A bell over the evening: the one nudge when today is still open.
private struct MiniNudge: View {
    @Environment(\.palette) private var palette
    var body: some View {
        HStack(spacing: 8) {
            Image("Icons/ui-bell").resizable().frame(width: 24, height: 24)
            Image("Icons/moon").resizable().frame(width: 18, height: 18).opacity(0.5)
        }
        .foregroundStyle(palette.ink)
    }
}

/// The app icons, small.
/// Swatches of the widget looks (Paper, Dot matrix, Outline, Receipt) and one app icon.
private struct MiniLooks: View {
    @Environment(\.palette) private var palette
    var body: some View {
        HStack(spacing: 5) {
            swatch(fill: .white, dot: Color(hex: 0x37352F), border: palette.hairline)
            swatch(fill: .black, dot: .white, border: .clear, round: true, glow: true)
            swatch(fill: .white, dot: Color(hex: 0x1F1E1B), border: Color(hex: 0x1F1E1B), round: true, outline: true)
            swatch(fill: Color(hex: 0xF4F4F2), dot: Color(hex: 0x262626), border: palette.hairline)
            Image("IconPreview-Night").resizable().frame(width: 26, height: 26).clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
    private func swatch(fill: Color, dot: Color, border: Color, round: Bool = false, outline: Bool = false, glow: Bool = false) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                let on = i != 1
                let shape = RoundedRectangle(cornerRadius: round ? 2.5 : 1.2, style: .continuous)
                ZStack {
                    if outline && !on { shape.stroke(dot, lineWidth: 1) } else { shape.fill(dot.opacity(on ? 1 : 0.3)) }
                    if glow && on { shape.stroke(dot.opacity(0.35), lineWidth: 2) }
                }
                .frame(width: 5, height: 5)
            }
        }
        .frame(width: 26, height: 26)
        .background(fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(border, lineWidth: 1))
    }
}

/// Two phones sharing one cloud.
private struct MiniSync: View {
    @Environment(\.palette) private var palette
    var body: some View {
        HStack(spacing: 8) {
            phone
            Image("Icons/ui-cloud").resizable().frame(width: 26, height: 26)
            phone
        }
    }
    private var phone: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(palette.ink, lineWidth: 1.5).frame(width: 14, height: 24)
            .overlay(RoundedRectangle(cornerRadius: 1).fill(palette.ink).frame(width: 7, height: 7))
    }
}

