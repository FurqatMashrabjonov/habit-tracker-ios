import Foundation
import AuthenticationServices
import CryptoKit
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseCrashlytics
import GoogleSignIn
import HabitData
import HabitDomain

/// Optional cloud copy of habits, days and notes in Firestore, the same documents the Android app
/// reads and writes, so one account links an Android phone and an iPhone. A Pro feature. The
/// database stays the source of truth: the app never waits on the network. Rules in HabitData/SyncRows.
@MainActor
@Observable
final class Sync {
    static let shared = Sync()

    private(set) var email: String?
    private(set) var running = false
    private(set) var lastSynced: Date? = UserDefaults.standard.object(forKey: "syncedAt") as? Date

    /// Built with a GoogleService-Info.plist; without one, sync stays hidden.
    let available: Bool

    private init() {
        available = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
        guard available else { return }
        FirebaseApp.configure()
        // Crash reports only (no analytics), and only from store builds: Xcode shows a dev crash better.
        #if DEBUG
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
        #else
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        #endif
        let settings = Firestore.firestore().settings
        settings.cacheSettings = MemoryCacheSettings() // the database is the offline copy
        Firestore.firestore().settings = settings
        email = Auth.auth().currentUser?.email ?? (Auth.auth().currentUser != nil ? "Apple Account" : nil)
    }

    var signedIn: Bool { available && Auth.auth().currentUser != nil }

    // ---- Running ------------------------------------------------------------------------------------

    private var pending: _Concurrency.Task<Void, Never>?

    /// Soon after a change; a newer request replaces a waiting one, so a burst of taps is one sync.
    func request(after seconds: Double = 5) {
        guard signedIn, Store.shared.active else { return }
        pending?.cancel()
        pending = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(for: .seconds(seconds))
            guard !_Concurrency.Task.isCancelled else { return }
            try? await run()
        }
    }

    /// Pull-to-refresh and "Sync now". ponytail: a 10 s cooldown is the app's only rate limit.
    func manual() async throws {
        if let lastSynced, Date().timeIntervalSince(lastSynced) < 10 { return }
        try await run()
    }

    func run() async throws {
        guard !running, Store.shared.active, available, let uid = Auth.auth().currentUser?.uid else { return }
        running = true
        defer { running = false }
        let store = AppModel.shared.store
        let defaults = UserDefaults.standard
        let start = Clock.nowMillis()
        let pushed = defaults.object(forKey: "syncPushed") as? Int64 ?? -1
        if pushed < 0 { try await store.markAllEdited() }
        let user = Firestore.firestore().collection("users").document(uid)
        try await push(store, user: user, since: max(pushed, 0))
        defaults.set(start, forKey: "syncPushed")
        try await store.clearTombstones(upTo: start)
        try await pull(store, user: user, start: start)
        lastSynced = Date()
        defaults.set(lastSynced, forKey: "syncedAt")
    }

    private func push(_ store: HabitStore, user: DocumentReference, since: Int64) async throws {
        let out = try await store.outbox(since: since)
        guard !out.isEmpty else { return }
        let habits = user.collection("habits"), months = user.collection("months")
        var ops: [(WriteBatch) -> Void] = []
        for uuid in out.deletedHabits {
            ops.append { $0.setData(["deleted": true, "updatedAt": FieldValue.serverTimestamp()], forDocument: habits.document(uuid)) }
            let docs = try await months.whereField("h", isEqualTo: uuid).getDocuments(source: .server).documents
            for d in docs { ops.append { $0.deleteDocument(d.reference) } }
        }
        for t in out.habits {
            var doc = CloudDoc.from(t)
            doc["updatedAt"] = FieldValue.serverTimestamp()
            // Android writes nulls for empty optional fields; merge would keep a stale value otherwise.
            for k in ["cue", "identity", "reminder", "schedule"] where doc[k] == nil { doc[k] = NSNull() }
            ops.append { $0.setData(doc, forDocument: habits.document(t.uuid)) }
        }
        for (id, m) in out.months {
            // Only maps with something in them: under a merge, an empty map would wipe the month's days.
            var fields: [String: Any] = ["h": m.habit, "m": m.month, "updatedAt": FieldValue.serverTimestamp()]
            if !m.days.isEmpty { fields["d"] = m.days }
            if !m.notes.isEmpty { fields["n"] = m.notes }
            ops.append { $0.setData(fields, forDocument: months.document(id), merge: true) }
        }
        // A batch takes up to 500 writes.
        for chunk in stride(from: 0, to: ops.count, by: 400).map({ Array(ops[$0..<min($0 + 400, ops.count)]) }) {
            let batch = Firestore.firestore().batch()
            chunk.forEach { $0(batch) }
            try await batch.commit()
        }
    }

    private func pull(_ store: HabitStore, user: DocumentReference, start: Int64) async throws {
        let defaults = UserDefaults.standard
        let (habitDocs, lastHabit) = try await changed(user.collection("habits"), after: defaults.object(forKey: "pulledHabits") as? Int64 ?? 0)
        for d in habitDocs {
            let data = d.data()
            _ = try await store.applyRemoteHabit(CloudDoc.tracker(uuid: d.documentID, data), deleted: data["deleted"] as? Bool == true, start: start)
        }
        defaults.set(lastHabit, forKey: "pulledHabits")
        let (monthDocs, lastMonth) = try await changed(user.collection("months"), after: defaults.object(forKey: "pulledMonths") as? Int64 ?? 0)
        for d in monthDocs {
            let data = d.data()
            guard let h = data["h"] as? String, let m = data["m"] as? String else { continue }
            let days = (data["d"] as? [String: Any] ?? [:]).compactMapValues { ($0 as? NSNumber)?.intValue }
            let notes = (data["n"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
            try await store.applyRemoteMonth(habit: h, month: m, days: days, notes: notes, start: start)
        }
        defaults.set(lastMonth, forKey: "pulledMonths")
    }

    /// Documents the server wrote after `after` (nanoseconds since 1970), and the newest such time.
    private func changed(_ c: CollectionReference, after: Int64) async throws -> ([QueryDocumentSnapshot], Int64) {
        let since = Timestamp(seconds: after / 1_000_000_000, nanoseconds: Int32(after % 1_000_000_000))
        let docs = try await c.whereField("updatedAt", isGreaterThan: since).order(by: "updatedAt").getDocuments(source: .server).documents
        let last = (docs.last?.get("updatedAt") as? Timestamp).map { $0.seconds * 1_000_000_000 + Int64($0.nanoseconds) } ?? after
        return (docs, last)
    }

    /// Forget sync progress (sign-in, sign-out, restore): the next run sends everything up again.
    func reset() {
        for k in ["syncPushed", "pulledHabits", "pulledMonths", "syncedAt"] { UserDefaults.standard.removeObject(forKey: k) }
        lastSynced = nil
    }

    // ---- Account ------------------------------------------------------------------------------------

    /// Signs in and merges: this phone's habits go up, the account's come down.
    func signInWithGoogle() async throws {
        let credential = try await googleCredential()
        try await signedIn(with: credential)
    }

    func signInWithApple(_ authorization: ASAuthorization) async throws {
        try await signedIn(with: appleCredential(authorization))
    }

    private func signedIn(with credential: AuthCredential) async throws {
        let result = try await Auth.auth().signIn(with: credential)
        email = result.user.email ?? "Apple Account"
        // Deletes made while signed out stay on this phone; they must not wipe the account's copy.
        try await AppModel.shared.store.clearTombstones(upTo: .max)
        reset()
        try await run()
    }

    func signOut() {
        try? Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
        email = nil
        reset()
    }

    /// Deletes the account and its cloud copy (App Store requires this in the app). Habits stay here.
    /// Firebase only deletes after a fresh sign-in, so Google users pick their account again; Apple
    /// users go through `deleteAppleAccount`.
    func deleteAccount() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        if isGoogleAccount { try await Auth.auth().currentUser?.reauthenticate(with: googleCredential()) }
        try await deleteCloudData(uid: uid)
        try await Auth.auth().currentUser?.delete()
        signOut()
    }

    /// Apple accounts confirm with Apple again (Firebase wants a fresh sign-in) and get their token revoked.
    func deleteAppleAccount(_ authorization: ASAuthorization) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await Auth.auth().currentUser?.reauthenticate(with: appleCredential(authorization))
        if let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
           let code = apple.authorizationCode.flatMap({ String(data: $0, encoding: .utf8) }) {
            try? await Auth.auth().revokeToken(withAuthorizationCode: code)
        }
        try await deleteCloudData(uid: uid)
        try await Auth.auth().currentUser?.delete()
        signOut()
    }

    var isGoogleAccount: Bool { Auth.auth().currentUser?.providerData.contains { $0.providerID == "google.com" } == true }

    private func deleteCloudData(uid: String) async throws {
        let user = Firestore.firestore().collection("users").document(uid)
        var refs: [DocumentReference] = []
        for name in ["habits", "months"] { refs += try await user.collection(name).getDocuments(source: .server).documents.map(\.reference) }
        for chunk in stride(from: 0, to: refs.count, by: 400).map({ Array(refs[$0..<min($0 + 400, refs.count)]) }) {
            let batch = Firestore.firestore().batch()
            chunk.forEach { batch.deleteDocument($0) }
            try await batch.commit()
        }
    }

    private func googleCredential() async throws -> AuthCredential {
        guard let clientID = FirebaseApp.app()?.options.clientID,
              let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first
        else { throw URLError(.userAuthenticationRequired) }
        var top = root
        while let next = top.presentedViewController { top = next }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: top)
        guard let idToken = result.user.idToken?.tokenString else { throw URLError(.userAuthenticationRequired) }
        return GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
    }

    // Sign in with Apple: a one-time nonce, hashed into the request and checked by Firebase.
    private(set) var nonce = ""

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        nonce = UUID().uuidString + UUID().uuidString
        request.requestedScopes = [.email]
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func appleCredential(_ authorization: ASAuthorization) throws -> AuthCredential {
        guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
              let token = apple.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else { throw URLError(.userAuthenticationRequired) }
        return OAuthProvider.appleCredential(withIDToken: token, rawNonce: nonce, fullName: apple.fullName)
    }
}
