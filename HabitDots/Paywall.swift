import SwiftUI
import HabitDesign

/// The paywall, as on Android: what Pro adds, yearly (with its free trial) or lifetime, and restore.
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
            Text("Tracking, widgets, reminders and your data stay free, with up to \(Store.freeHabits) habits. Pro adds:")
                .font(Type.bodyMedium).foregroundStyle(palette.dim)
            VStack(alignment: .leading, spacing: 10) {
                feature("ui-dots-nine", "Unlimited habits")
                feature("ui-cloud", "Sync across your phones")
                feature("ui-chart-bar", "Statistics")
                feature("ui-palette-line", "Widget looks and layouts, compact habit cards")
            }
            HStack(spacing: 10) {
                plan(Store.yearly, "Yearly", store.price(Store.yearly) ?? "$11.99", trial.map { "\($0) days free" })
                plan(Store.lifetime, "Lifetime", store.price(Store.lifetime) ?? "$29.99", "Pay once")
            }
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
        .presentationDetents([.height(560), .large])
        .textCap()
        .presentationCornerRadius(Radius.sheet)
        .presentationBackground(palette.surfaceLow)
        .overlay(alignment: .bottom) {
            if let message { Toast(text: message).task { try? await _Concurrency.Task.sleep(for: .seconds(2)); self.message = nil } }
        }
        .animation(.snappy, value: message)
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image("Icons/\(icon)").resizable().frame(width: 20, height: 20)
            Text(text).font(Type.bodyLarge)
        }
    }

    private func plan(_ id: String, _ title: String, _ price: String, _ note: String?) -> some View {
        let selected = choice == id
        return Button { choice = id } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Type.labelLarge).foregroundStyle(palette.dim)
                // Long local prices shrink to fit one line instead of wrapping.
                Text(price).font(Type.titleLarge).lineLimit(1).minimumScaleFactor(0.5)
                if let note { Text(note).font(Type.labelMedium).foregroundStyle(palette.dim) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(palette.surfaceLow, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .stroke(selected ? palette.ink : palette.hairline, lineWidth: selected ? 2 : 1))
            .animation(.easeOut(duration: 0.2), value: selected)
        }
        .buttonStyle(.plain)
    }
}
