import Foundation
import Testing
import HabitData
@testable import HabitDots

/// The gates around Pro. Purchases themselves go through RevenueCat (its Test Store in debug
/// builds), which needs the network and a tap on its dialog, so they are checked by hand.
@MainActor
@Suite(.serialized) struct StoreTests {
    init() {
        UserDefaults.standard.removeObject(forKey: "plan")
        UserDefaults.standard.set(false, forKey: "pretendPro")
    }

    @Test func freeUsersKeepFourHabits() {
        let store = Store()
        #expect(!store.active)
        #expect(store.canAddHabit(activeHabits: 3))
        #expect(!store.canAddHabit(activeHabits: Store.freeHabits))
    }

    @Test func requireOpensThePaywallOnlyWithoutPro() {
        let store = Store()
        #expect(!store.require())
        #expect(store.paywall)
    }

    @Test func lastKnownPlanUnlocksOffline() {
        UserDefaults.standard.set(Store.lifetime, forKey: "plan")
        let store = Store()
        #expect(store.active)
        #expect(store.plan == Store.lifetime)
        #expect(store.canAddHabit(activeHabits: 50))
        #expect(store.require())
    }

    @Test func pricesWaitForTheStore() {
        let store = Store()
        #expect(store.price(Store.yearly) == nil)
        #expect(store.lifetimeInYears == nil)
        #expect(store.trialDays == nil)
    }
}
