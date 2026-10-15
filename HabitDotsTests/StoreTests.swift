import StoreKitTest
import Testing
import HabitData
@testable import HabitDots

/// The real purchase flow against Products.storekit, no App Store account needed.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct StoreTests {
    let session: SKTestSession

    init() throws {
        session = try SKTestSession(configurationFileNamed: "Products")
        session.disableDialogs = true
        session.clearTransactions()
        UserDefaults.standard.removeObject(forKey: "plan")
        UserDefaults.standard.set(false, forKey: "pretendPro")
    }

    @Test func productsLoadWithPricesAndTrial() async throws {
        let store = Store()
        await store.start()
        #expect(store.price(Store.yearly) != nil)
        #expect(store.price(Store.lifetime) != nil)
        #expect(store.trialDays == 7)
        #expect(!store.active)
        #expect(store.canAddHabit(activeHabits: 4))
        #expect(!store.canAddHabit(activeHabits: 5))
    }

    @Test func buyingLifetimeUnlocksProAndTheWidgets() async throws {
        let store = Store()
        await store.start()
        #expect(await store.buy(Store.lifetime) == .bought)
        #expect(store.active)
        #expect(store.plan == Store.lifetime)
        #expect(Shared.pro)
        #expect(store.canAddHabit(activeHabits: 50))
    }

    @Test func yearlyTrialCountsAsPro_refundTakesItAway() async throws {
        let store = Store()
        await store.start()
        #expect(await store.buy(Store.yearly) == .bought)
        #expect(store.plan == Store.yearly)
        let all = session.allTransactions()
        let t = try #require(all.first { $0.productIdentifier == Store.yearly })
        try session.refundTransaction(identifier: UInt(t.identifier))
        // StoreKit reports the refund through Transaction.updates; give it a moment.
        for _ in 0..<20 where store.active {
            try await _Concurrency.Task.sleep(for: .milliseconds(100))
            await store.refresh()
        }
        #expect(!store.active)
        #expect(!Shared.pro)
    }
}
