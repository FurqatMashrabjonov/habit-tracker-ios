import Foundation
import WidgetKit
import FirebaseAuth
import RevenueCat
import HabitData

/// HabitDots Pro: unlimited habits, evening check-in, home screen looks and sync. Free covers
/// everything else for good. Sold through RevenueCat on top of the App Store: `pro_yearly`
/// (subscription with a free trial) or `pro_lifetime` (one-time), the same product ids as on Google
/// Play. One entitlement, `pro`, shared with the Android app: the RevenueCat user is the Firebase
/// account, so Pro bought on either phone unlocks both once signed in.
@MainActor
@Observable
final class Store {
    static let shared = Store()
    init() {}
    static let yearly = "pro_yearly"
    static let lifetime = "pro_lifetime"
    static let freeHabits = 4
    private static let entitlement = "pro"

    // Public SDK keys (safe to ship). Debug builds use RevenueCat's Test Store, so purchases can be
    // tried in the simulator without an App Store account.
    #if DEBUG
    private static let apiKey = "test_WyqyQuELbZSupwZnSOhFWrqwGQe"
    #else
    private static let apiKey = "appl_MLzsPhcPtuDTWqNIQLPWSHUzljE"
    #endif

    /// Which plan is owned: `yearly`, `lifetime` or nil. Starts from the last known state, so an
    /// offline start doesn't lock a paying user out.
    private(set) var plan: String? = UserDefaults.standard.string(forKey: "plan")
    /// The current offering's packages by product id, once RevenueCat answers.
    private(set) var products: [String: Package] = [:]
    /// Debug builds can pretend to own Pro, to try both sides (Settings).
    var pretend = UserDefaults.standard.bool(forKey: "pretendPro") {
        didSet { UserDefaults.standard.set(pretend, forKey: "pretendPro"); publish() }
    }
    /// Set to show the paywall from anywhere.
    var paywall = false

    var active: Bool { plan != nil || (Pro.debuggable && pretend) }

    private var updates: _Concurrency.Task<Void, Never>?
    private var auth: AuthStateDidChangeListenerHandle?

    func start() async {
        publish()
        guard !Purchases.isConfigured else { return }
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        let signedIn = Sync.shared.available ? Auth.auth().currentUser?.uid : nil
        Purchases.configure(with: Configuration.Builder(withAPIKey: Self.apiKey).with(appUserID: signedIn).build())
        // Renewals, refunds and purchases from the other phone all land here.
        updates = _Concurrency.Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream { self?.own(info) }
        }
        // The RevenueCat user follows the Google account: sign-in links Pro across phones,
        // sign-out (or deleting the account) leaves it behind.
        if Sync.shared.available {
            auth = Auth.auth().addStateDidChangeListener { _, user in
                let uid = user?.uid
                _Concurrency.Task { @MainActor in
                    let p = Purchases.shared
                    if let uid, uid != p.appUserID {
                        if let (info, _) = try? await p.logIn(uid) { Store.shared.own(info) }
                    } else if uid == nil, !p.isAnonymous {
                        if let info = try? await p.logOut() { Store.shared.own(info) }
                    }
                }
            }
        }
        await refresh()
        if let offering = try? await Purchases.shared.offerings().current {
            products = Dictionary(offering.availablePackages.compactMap { p in
                let id = p.storeProduct.productIdentifier
                return id == Self.yearly || id == Self.lifetime ? (id, p) : nil
            }, uniquingKeysWith: { a, _ in a })
        }
    }

    /// Asks RevenueCat what this user owns.
    func refresh() async {
        guard Purchases.isConfigured, let info = try? await Purchases.shared.customerInfo() else { return }
        own(info)
    }

    private func own(_ info: CustomerInfo) {
        guard let pro = info.entitlements[Self.entitlement], pro.isActive else { return set(nil) }
        set(pro.productIdentifier == Self.lifetime ? Self.lifetime : Self.yearly)
    }

    private func set(_ owned: String?) {
        plan = owned
        UserDefaults.standard.set(plan, forKey: "plan")
        publish()
    }

    enum Outcome { case bought, pending, cancelled, failed }

    func buy(_ id: String) async -> Outcome {
        guard let package = products[id] else { return .failed }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return .cancelled }
            own(result.customerInfo)
            return active ? .bought : .pending
        } catch let error as ErrorCode where error == .paymentPendingError {
            return .pending
        } catch { return .failed }
    }

    /// "Restore purchase": syncs with the App Store (may ask to sign in), then re-reads.
    func restore() async -> Bool {
        if let info = try? await Purchases.shared.restorePurchases() { own(info) }
        return active
    }

    /// Shows the paywall unless Pro is active; returns whether the gated action may go ahead.
    func require() -> Bool {
        if !active { paywall = true }
        return active
    }

    func canAddHabit(activeHabits: Int) -> Bool { active || activeHabits < Self.freeHabits }

    func price(_ id: String) -> String? { products[id]?.storeProduct.localizedPriceString }

    /// The yearly price spread over twelve months, in the store's currency ("$0.67").
    var monthlyOfYearly: String? { products[Self.yearly]?.storeProduct.localizedPricePerMonth }

    /// How many years of the yearly plan the lifetime price equals; the paywall's anchor.
    var lifetimeInYears: Double? {
        guard let y = products[Self.yearly]?.storeProduct.price, let l = products[Self.lifetime]?.storeProduct.price, y > 0 else { return nil }
        return NSDecimalNumber(decimal: l / y).doubleValue
    }

    /// Free trial length in days on the yearly plan, if offered.
    var trialDays: Int? {
        guard let offer = products[Self.yearly]?.storeProduct.introductoryDiscount, offer.paymentMode == .freeTrial else { return nil }
        let p = offer.subscriptionPeriod
        switch p.unit {
        case .day: return p.value
        case .week: return p.value * 7
        case .month: return p.value * 30
        case .year: return p.value * 365
        @unknown default: return nil
        }
    }

    /// The widgets read Pro from the shared folder: their looks fall back to Paper/Night without it.
    private func publish() {
        if Shared.pro != active {
            Shared.pro = active
            WidgetCenter.shared.reloadAllTimelines()
        }
        if active { paywall = false }
    }
}
