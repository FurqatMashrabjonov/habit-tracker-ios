import SwiftUI
import UniformTypeIdentifiers
import HabitData
import HabitDesign
import HabitDomain

/// Settings as a sheet, HabitKit-style: one list of rows, each opening its own page inside the sheet.
struct SettingsSheet: View {
    let onOpenHabit: (Int64) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @AppStorage("theme") private var theme = ThemeMode.system
    @State private var store = Store.shared
    @State private var paywall = false
    @State private var archived: [Tracker] = []
    @State private var trash: [TrashedHabit] = []

    var body: some View {
        NavigationStack {
            Page {
                RowGroup {
                    Row(label: "HabitDots Pro", icon: "ui-sparkle-fill", value: store.active ? "Active" : nil, chevron: !store.active) {
                        if !store.active { paywall = true }
                    }
                    if Pro.debuggable {
                        Row(label: "Pretend Pro (debug)", chevron: false, checked: store.pretend) { store.pretend.toggle() }
                    }
                }
                GroupTitle("App")
                RowGroup {
                    NavRow(label: "Appearance", icon: "ui-palette-line", value: theme.label) { AppearancePage() }
                    NavRow(label: "Archive", icon: "ui-archive", value: "\(archived.count)") {
                        ArchivedPage(archived: archived) { id in dismiss(); onOpenHabit(id) }
                    }
                    NavRow(label: "Recently deleted", icon: "ui-trash", value: "\(trash.count)") { TrashPage() }
                }
                GroupTitle("Data")
                RowGroup {
                    if Sync.shared.available {
                        NavRow(label: "Sync", icon: "ui-cloud", value: Sync.shared.email ?? "Off") { SyncPage() }
                    }
                    NavRow(label: "Backup & restore", icon: "ui-database") { DataPage() }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image("Icons/ui-x").resizable().frame(width: 18, height: 18) }.accessibilityLabel("Close")
                }
            }
        }
        .presentationDetents([.large])
        .textCap()
        .presentationCornerRadius(Radius.sheet)
        .presentationBackground(palette.surfaceLow)
        .sheet(isPresented: $paywall) { Paywall() }
        .task {
            let store = model.store
            async let a = store.trackers(includeArchived: true)
            async let t = store.trash()
            archived = ((try? await a) ?? []).filter(\.archived)
            trash = (try? await t) ?? []
        }
    }
}

// --- Pages ---------------------------------------------------------------------------------------

private struct AppearancePage: View {
    @AppStorage("theme") private var theme = ThemeMode.system
    @AppStorage("cards") private var cards = CardStyle.wall
    @State private var paywall = false
    var body: some View {
        Page {
            GroupTitle("App")
            RowGroup {
                ForEach(ThemeMode.allCases, id: \.self) { m in Row(label: m.label, chevron: false, checked: theme == m) { theme = m } }
            }
            GroupTitle("Habit cards")
            RowGroup {
                ForEach(CardStyle.allCases, id: \.self) { s in
                    Row(label: s.label, value: s != .wall && !Store.shared.active ? "Pro" : nil, chevron: false, checked: cards == s) {
                        if s == .wall || Store.shared.active { cards = s } else { paywall = true }
                    }
                }
            }
        }
        .navigationTitle("Appearance")
        .sheet(isPresented: $paywall) { Paywall() }
    }
}

private struct ArchivedPage: View {
    let archived: [Tracker]
    let onOpen: (Int64) -> Void
    @Environment(\.palette) private var palette
    var body: some View {
        Page {
            if archived.isEmpty {
                Text("Nothing archived. Archived habits keep their history and leave the home screen.")
                    .font(Type.bodyMedium).foregroundStyle(palette.dim).padding(4)
            } else {
                RowGroup { ForEach(archived, id: \.uuid) { t in Row(label: t.name, icon: nil) { onOpen(t.id ?? 0) } } }
            }
        }
        .navigationTitle("Archive")
    }
}

private struct TrashPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var items: [TrashedHabit] = []
    @State private var restored: String?
    var body: some View {
        Page {
            if !items.isEmpty {
                RowGroup {
                    ForEach(items, id: \.uuid) { item in
                        let left = max(Trash.keepDays - Int((Clock.nowMillis() - item.deletedAt) / 86_400_000), 1)
                        Row(label: item.name, value: "\(left) days left", chevron: false) {
                            _Concurrency.Task {
                                try? await model.store.restore(item)
                                restored = item.name
                                items = (try? await model.store.trash()) ?? []
                            }
                        }
                    }
                }
            }
            FootNote(items.isEmpty ? "Nothing here. Deleted habits stay for 30 days." : "Tap a habit to bring it back with its whole history.")
        }
        .navigationTitle("Recently deleted")
        .task { items = (try? await model.store.trash()) ?? [] }
        .overlay(alignment: .bottom) {
            if let restored { Toast(text: "Restored “\(restored)”").task { try? await _Concurrency.Task.sleep(for: .seconds(2)); self.restored = nil } }
        }
        .animation(.snappy, value: restored)
    }
}

private struct DataPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var share: URL?
    @State private var importing = false
    @State private var pending: URL?
    @State private var message: String?
    @State private var copies: [Backups.Copy] = []

    var body: some View {
        Page {
            RowGroup {
                Row(label: "Back up") { share = try? Backups.exportCopy(model.store) }
                Row(label: "Restore from file") { importing = true }
                Row(label: "Export as CSV") { _Concurrency.Task { share = try? await Backups.csv(model.store) } }
            }
            GroupTitle("Automatic backups")
            if !copies.isEmpty {
                RowGroup {
                    ForEach(copies) { c in
                        Row(label: c.modified.formatted(date: .abbreviated, time: .omitted),
                            value: c.url.lastPathComponent.contains("before-restore") ? "Before restore" : nil) { pending = c.url }
                    }
                }
            }
            FootNote("Once a week a copy goes to Files › On My iPhone › HabitDots, the last five are kept. A backup from the Android app opens here too.")
        }
        .navigationTitle("Backup & restore")
        .onAppear { copies = Backups.list() }
        .sheet(item: $share) { url in ShareSheet(items: [url]).presentationDetents([.medium, .large]) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .item]) { result in
            guard case .success(let picked) = result else { return }
            // A private copy: the picked file may sit in iCloud or another app's folder.
            let ok = picked.startAccessingSecurityScopedResource()
            defer { if ok { picked.stopAccessingSecurityScopedResource() } }
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("restore-\(UUID().uuidString).db")
            do { try FileManager.default.copyItem(at: picked, to: copy); pending = copy } catch { message = "Not a valid backup file" }
        }
        .confirmationDialog("Restore this backup?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button("Restore", role: .destructive) {
                guard let url = pending else { return }
                do { try model.restore(from: url); message = "Backup restored"; copies = Backups.list() } catch { message = "Not a valid backup file" }
                pending = nil
            }
        } message: {
            Text("It replaces all habits, days and notes on this phone. The current data is saved to the automatic backups first, so you can go back.")
        }
        .overlay(alignment: .bottom) {
            if let message { Toast(text: message).task { try? await _Concurrency.Task.sleep(for: .seconds(2)); self.message = nil } }
        }
        .animation(.snappy, value: message)
    }
}

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// --- Building blocks (Android's RowGroup / GroupTitle) -------------------------------------------

/// A scrolling settings page on the sheet's background.
struct Page<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.palette) private var palette
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 0) { content }.padding(.horizontal, 16).padding(.bottom, 32) }
            .background(palette.surfaceLow)
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// Section title above a `RowGroup`.
struct GroupTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    @Environment(\.palette) private var palette
    var body: some View {
        Text(text.uppercased()).font(Type.labelMedium).tracking(0.4).foregroundStyle(palette.dim)
            .padding(.leading, 4).padding(.top, 16).padding(.bottom, 6)
    }
}

/// Small print under a group.
struct FootNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    @Environment(\.palette) private var palette
    var body: some View { Text(text).font(Type.bodySmall).foregroundStyle(palette.dim).padding(.leading, 4).padding(.top, 8) }
}

/// Rounded group of rows with hairline dividers between them.
struct RowGroup<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    if i > 0 { Divider().overlay(palette.hairline).padding(.leading, 16) }
                    row
                }
            }
        }
        .background(palette.background, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).stroke(palette.softBorder, lineWidth: 1))
    }
}

/// A settings row: icon tile, label, optional value, and a chevron when it opens something.
struct Row: View {
    let label: String
    var icon: String? = nil
    var value: String? = nil
    var chevron = true
    var checked = false
    let action: () -> Void
    var body: some View { Button(action: action) { RowLabel(label: label, icon: icon, value: value, chevron: chevron, checked: checked) }.buttonStyle(RowPress()) }
}

/// A row that pushes a page.
struct NavRow<Destination: View>: View {
    let label: String
    var icon: String? = nil
    var value: String? = nil
    @ViewBuilder let destination: () -> Destination
    var body: some View {
        NavigationLink(destination: destination) { RowLabel(label: label, icon: icon, value: value, chevron: true, checked: false) }.buttonStyle(RowPress())
    }
}

struct RowLabel: View {
    let label: String
    let icon: String?
    let value: String?
    let chevron: Bool
    let checked: Bool
    @Environment(\.palette) private var palette
    var body: some View {
        HStack(spacing: 14) {
            if let icon {
                Image("Icons/\(icon)").resizable().frame(width: 18, height: 18)
                    .frame(width: 32, height: 32)
                    .background(palette.tile, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            }
            Text(label).font(Type.bodyLarge).foregroundStyle(palette.ink)
            Spacer(minLength: 8)
            if let value { Text(value).font(Type.bodyMedium).foregroundStyle(palette.dim) }
            if checked { Image("Icons/ui-check").resizable().frame(width: 20, height: 20) }
            if chevron { Image("Icons/ui-caret-right").resizable().frame(width: 16, height: 16).foregroundStyle(palette.dim) }
        }
        .foregroundStyle(palette.ink)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct RowPress: ButtonStyle {
    @Environment(\.palette) private var palette
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? palette.tile : .clear)
    }
}

/// A short message at the bottom of the screen.
struct Toast: View {
    let text: String
    @Environment(\.palette) private var palette
    var body: some View {
        Text(text).font(Type.labelLarge).foregroundStyle(palette.onInk)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(palette.ink, in: Capsule())
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// ---- Sync -----------------------------------------------------------------------------------------

import AuthenticationServices

/// Sign in for sync (Apple or Google), the sync state, sign-out and account deletion.
struct SyncPage: View {
    @Environment(\.palette) private var palette
    @State private var sync = Sync.shared
    @State private var store = Store.shared
    @State private var busy = false
    @State private var confirmDelete = false
    @State private var appleDelete = false
    @State private var paywall = false
    @State private var message: String?

    var body: some View {
        Page {
            if sync.email == nil {
                Text("Keep your habits on every phone you sign in to, Android or iPhone. Nothing leaves this phone until you sign in."
                     + (store.active ? "" : " Sync is part of Pro."))
                    .font(Type.bodyMedium).foregroundStyle(palette.dim).padding(.horizontal, 4).padding(.bottom, 12)
                if store.active {
                    SignInWithAppleButton(.signIn) { sync.prepareAppleRequest($0) } onCompletion: { result in
                        guard case .success(let auth) = result else { return }
                        act("Couldn't sign in", "Signed in") { try await sync.signInWithApple(auth) }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .clipShape(Capsule())
                    .padding(.bottom, 10)
                    RowGroup { Row(label: "Sign in with Google", icon: "ui-cloud", chevron: false) { act("Couldn't sign in", "Signed in") { try await sync.signInWithGoogle() } } }
                } else {
                    RowGroup { Row(label: "Get Pro", icon: "ui-sparkle-fill") { paywall = true } }
                }
            } else {
                GroupTitle("Account")
                RowGroup {
                    Row(label: sync.email ?? "", icon: "ui-cloud", chevron: false) {}
                    Row(label: "Sync now", value: sync.running ? "Syncing…" : sync.lastSynced.map { $0.formatted(.relative(presentation: .named)) } ?? "Never", chevron: false) {
                        act("Sync failed", "Synced") { try await sync.manual() }
                    }
                }
                Spacer().frame(height: 12)
                RowGroup {
                    Row(label: "Sign out", chevron: false) { sync.signOut(); message = "Signed out" }
                    Row(label: "Delete account", chevron: false) { confirmDelete = true }
                }
            }
        }
        .navigationTitle("Sync")
        .disabled(busy)
        .sheet(isPresented: $paywall) { Paywall() }
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            if sync.isGoogleAccount {
                Button("Delete", role: .destructive) { act("Couldn't delete the account", "Account deleted") { try await sync.deleteAccount() } }
            } else {
                Button("Delete", role: .destructive) { appleDelete = true }
            }
        } message: {
            Text("Your habits are removed from the cloud and your account is closed. The habits on this phone stay.")
        }
        .sheet(isPresented: $appleDelete) {
            // Firebase deletes only after a fresh sign-in: confirm with Apple once more.
            VStack(spacing: 16) {
                Text("Confirm with Apple to delete your account.").font(Type.bodyLarge).multilineTextAlignment(.center)
                SignInWithAppleButton(.continue) { sync.prepareAppleRequest($0) } onCompletion: { result in
                    appleDelete = false
                    guard case .success(let auth) = result else { return }
                    act("Couldn't delete the account", "Account deleted") { try await sync.deleteAppleAccount(auth) }
                }
                .signInWithAppleButtonStyle(.black).frame(height: 50).clipShape(Capsule())
            }
            .padding(24)
            .presentationDetents([.height(200)])
            .textCap()
        }
        .overlay(alignment: .bottom) {
            if let message { Toast(text: message).task { try? await _Concurrency.Task.sleep(for: .seconds(2)); self.message = nil } }
        }
        .animation(.snappy, value: message)
    }

    private func act(_ failure: String, _ success: String, _ work: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        _Concurrency.Task {
            do { try await work(); message = success } catch { message = failure }
            busy = false
        }
    }
}
