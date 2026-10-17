import Foundation
import StoreKit
import WidgetKit
import HabitData

/// HabitDots Pro: unlimited habits, sync, statistics and widget looks. Free covers everything else
/// for good. Sold through the App Store: `pro_yearly` (subscription with a free trial) or
/// `pro_lifetime` (one-time), the same product ids as on Google Play.
///
/// ponytail: entitlement is checked on the phone with StoreKit 2's signed transactions; add server
/// verification (App Store Server API) if piracy ever matters.
@MainActor
@Observable
final class Store {
    static let shared = Store()
    init() {}
    static let yearly = "pro_yearly"
    static let lifetime = "pro_lifetime"
    static let freeHabits = 4

    /// Which plan is owned: `yearly`, `lifetime` or nil. Starts from the last known state, so an
    /// offline start doesn't lock a paying user out.
    private(set) var plan: String? = UserDefaults.standard.string(forKey: "plan")
    private(set) var products: [String: Product] = [:]
    /// Debug builds can pretend to own Pro, to try both sides (Settings).
    var pretend = UserDefaults.standard.bool(forKey: "pretendPro") {
        didSet { UserDefaults.standard.set(pretend, forKey: "pretendPro"); publish() }
    }
    /// Set to show the paywall from anywhere.
    var paywall = false

    var active: Bool { plan != nil || (Pro.debuggable && pretend) }

    private var updates: _Concurrency.Task<Void, Never>?

    func start() async {
        publish()
        // Purchases made elsewhere (another device, Ask to Buy, a renewal) arrive here.
        updates = _Concurrency.Task {
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self.refresh()
            }
        }
        await refresh()
        if let loaded = try? await Product.products(for: [Self.yearly, Self.lifetime]) {
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        }
    }

    /// Asks the App Store what this Apple Account owns.
    func refresh() async {
        var owned: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.revocationDate == nil { owned.insert(t.productID) }
        }
        plan = owned.contains(Self.lifetime) ? Self.lifetime : owned.contains(Self.yearly) ? Self.yearly : nil
        UserDefaults.standard.set(plan, forKey: "plan")
        publish()
    }

    enum Outcome { case bought, pending, cancelled, failed }

    func buy(_ id: String) async -> Outcome {
        guard let product = products[id] else { return .failed }
        do {
            switch try await product.purchase() {
            case .success(.verified(let t)):
                await t.finish()
                await refresh()
                return .bought
            case .success(.unverified): return .failed
            case .pending: return .pending
            case .userCancelled: return .cancelled
            @unknown default: return .failed
            }
        } catch { return .failed }
    }

    /// "Restore purchase": syncs with the App Store (may ask to sign in), then re-reads.
    func restore() async -> Bool {
        try? await AppStore.sync()
        await refresh()
        return active
    }

    /// Shows the paywall unless Pro is active; returns whether the gated action may go ahead.
    func require() -> Bool {
        if !active { paywall = true }
        return active
    }

    func canAddHabit(activeHabits: Int) -> Bool { active || activeHabits < Self.freeHabits }

    func price(_ id: String) -> String? { products[id]?.displayPrice }

    /// Free trial length in days on the yearly plan, if offered.
    var trialDays: Int? {
        guard let offer = products[Self.yearly]?.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        let p = offer.period
        switch p.unit {
        case .day: return p.value
        case .week: return p.value * 7
        case .month: return p.value * 30
        case .year: return p.value * 365
        @unknown default: return nil
        }
    }

    /// The widgets read Pro from the shared folder.
    private func publish() {
        if Shared.pro != active {
            Shared.pro = active
            WidgetCenter.shared.reloadAllTimelines()
        }
        if active { paywall = false }
    }
}
