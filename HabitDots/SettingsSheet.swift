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
    @AppStorage("nudge", store: Shared.defaults) private var nudge = false
    @AppStorage("nudgeAt", store: Shared.defaults) private var nudgeAt = 21 * 3600

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
                        ArchivedPage(archived: archived, onUnarchive: unarchive)
                    }
                    NavRow(label: "Recently deleted", icon: "ui-trash", value: "\(trash.count)") { TrashPage() }
                }
                // Pro: the label says so up front; without Pro a tap opens the paywall.
                RowGroup {
                    if store.active {
                        NavRow(label: "Evening check-in", icon: "ui-bell", value: nudge ? ClockTime(secondOfDay: nudgeAt).description : "Off") { NudgePage() }
                        NavRow(label: "App icon", icon: "ui-squares-four", value: AppIconChoice.current.name) { IconPage() }
                    } else {
                        Row(label: "Evening check-in", icon: "ui-bell", value: "Pro") { paywall = true }
                        Row(label: "App icon", icon: "ui-squares-four", value: "Pro") { paywall = true }
                    }
                }
                GroupTitle("Data")
                RowGroup {
                    if Sync.shared.available {
                        NavRow(label: "Sync", icon: "ui-cloud", value: Sync.shared.email ?? "Off") { SyncPage() }
                    }
                    NavRow(label: "Backup & restore", icon: "ui-database") { DataPage() }
                }
                GroupTitle("About")
                RowGroup {
                    Row(label: "Privacy policy") { open("https://habitdots-app.web.app/privacy") }
                    Row(label: "Terms of use") { open("https://habitdots-app.web.app/terms") }
                    NavRow(label: "Open-source licenses") { LicensesPage() }
                }
                Text("HabitDots \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(Type.bodySmall).foregroundStyle(palette.dim)
                    .frame(maxWidth: .infinity).padding(.top, 16)
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
        .task { await load() }
    }

    private func load() async {
        let store = model.store
        async let a = store.trackers(includeArchived: true)
        async let t = store.trash()
        archived = ((try? await a) ?? []).filter(\.archived)
        trash = (try? await t) ?? []
    }

    /// Back onto the home screen; past the free limit that's a Pro feature.
    private func unarchive(_ t: Tracker) {
        // The paywall has to be this sheet's own: one presented from the root can't show over Settings.
        guard Store.shared.canAddHabit(activeHabits: model.rows?.count ?? 0) else { paywall = true; return }
        var t = t
        t.archived = false
        let store = model.store
        _Concurrency.Task { _ = try? await store.save(t); await load() }
    }

    private func open(_ url: String) { UIApplication.shared.open(URL(string: url)!) }
}

// --- Pages ---------------------------------------------------------------------------------------

private struct LicensesPage: View {
    var body: some View {
        Page {
            Text("""
            HabitDots is built with:

            Firebase (Auth, Cloud Firestore), GoogleSignIn and their Google dependencies: Apache License 2.0.

            GRDB.swift: MIT License.

            Phosphor Icons: MIT License.

            Full license texts: apache.org/licenses/LICENSE-2.0 and opensource.org/license/mit.
            """)
            .font(Type.bodyMedium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
        .navigationTitle("Licenses")
    }
}

/// Only the app's theme: card styles live on the home screen, widget themes in each widget's settings.
private struct AppearancePage: View {
    @AppStorage("theme") private var theme = ThemeMode.system
    var body: some View {
        Page {
            RowGroup {
                ForEach(ThemeMode.allCases, id: \.self) { m in Row(label: m.label, chevron: false, checked: theme == m) { theme = m } }
            }
        }
        .navigationTitle("Appearance")
    }
}

private struct ArchivedPage: View {
    let archived: [Tracker]
    let onUnarchive: (Tracker) -> Void
    @Environment(\.palette) private var palette
    var body: some View {
        Page {
            if archived.isEmpty {
                Text("Nothing archived. Archived habits keep their history and leave the home screen.")
                    .font(Type.bodyMedium).foregroundStyle(palette.dim).padding(4)
            } else {
                RowGroup { ForEach(archived, id: \.uuid) { t in Row(label: t.name, icon: nil, value: "Unarchive", chevron: false) { onUnarchive(t) } } }
                Text("Tap a habit to bring it back to the home screen with its whole history.")
                    .font(Type.bodySmall).foregroundStyle(palette.dim).padding(.horizontal, 4)
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
    @State private var paywall = false
    var body: some View {
        Page {
            if !items.isEmpty {
                RowGroup {
                    ForEach(items, id: \.uuid) { item in
                        let left = max(Trash.keepDays - Int((Clock.nowMillis() - item.deletedAt) / 86_400_000), 1)
                        Row(label: item.name, value: "\(left) days left", chevron: false) {
                            // Bringing one back counts against the free limit, like unarchiving.
                            guard Store.shared.canAddHabit(activeHabits: model.rows?.count ?? 0) else { paywall = true; return }
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
        .sheet(isPresented: $paywall) { Paywall() }
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
            Text(label).font(Type.bodyLarge).foregroundStyle(palette.ink).lineLimit(1).layoutPriority(1)
            Spacer(minLength: 8)
            // A long value (an email) truncates instead of squeezing the label.
            if let value { Text(value).font(Type.bodyMedium).foregroundStyle(palette.dim).lineLimit(1) }
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


/// Sign in for sync (Google), the sync state, sign-out and account deletion.
struct SyncPage: View {
    @Environment(\.palette) private var palette
    @State private var sync = Sync.shared
    @State private var store = Store.shared
    @State private var busy = false
    @State private var confirmDelete = false
    @State private var paywall = false
    @State private var message: String?

    var body: some View {
        Page {
            if sync.email == nil {
                Text("Keep your habits on every phone you sign in to, Android or iPhone. Nothing leaves this phone until you sign in."
                     + (store.active ? "" : " Sync is part of Pro."))
                    .font(Type.bodyMedium).foregroundStyle(palette.dim).padding(.horizontal, 4).padding(.bottom, 12)
                if store.active {
                    RowGroup { Row(label: "Sign in with Google", icon: "ui-cloud", chevron: false) { act("Couldn't sign in", "Signed in") { try await sync.signInWithGoogle() } } }
                } else {
                    RowGroup { Row(label: "Get Pro", icon: "ui-sparkle-fill") { paywall = true } }
                }
            } else {
                // Signed in but Pro lapsed: say why nothing syncs, and offer Pro instead of a button that does nothing.
                if !store.active {
                    Text("Sync is paused: it's part of HabitDots Pro. Everything stays on this phone, and syncs again with Pro.")
                        .font(Type.bodyMedium).foregroundStyle(palette.dim).padding(.horizontal, 4).padding(.bottom, 12)
                }
                GroupTitle("Account")
                RowGroup {
                    Row(label: sync.email ?? "", icon: "ui-cloud", chevron: false) {}
                    if !store.active {
                        Row(label: "Get Pro", icon: "ui-sparkle-fill") { paywall = true }
                    } else {
                        Row(label: "Sync now", value: sync.running ? "Syncing…" : sync.lastSynced.map { $0.formatted(.relative(presentation: .named)) } ?? "Never", chevron: false) {
                            act("Sync failed", "Synced") { try await sync.manual() }
                        }
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
            Button("Delete", role: .destructive) { act("Couldn't delete the account", "Account deleted") { try await sync.deleteAccount() } }
        } message: {
            Text("Your habits are removed from the cloud and your account is closed. The habits on this phone stay.")
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

/// Pro's evening check-in: on or off, and when.
private struct NudgePage: View {
    @Environment(AppModel.self) private var model
    @AppStorage("nudge", store: Shared.defaults) private var on = false
    @AppStorage("nudgeAt", store: Shared.defaults) private var at = 21 * 3600
    @State private var picking = false
    var body: some View {
        Page {
            RowGroup {
                Row(label: "Evening check-in", chevron: false, checked: on) {
                    on.toggle()
                    if on { Reminders.askPermission() }
                    model.remindersChanged()
                }
                if on { Row(label: "Time", value: ClockTime(secondOfDay: at).description) { picking = true } }
            }
            FootNote("At this time, if any of today's habits is still open, one quiet notification lists them. On days you're done, nothing comes.")
        }
        .navigationTitle("Evening check-in")
        .sheet(isPresented: $picking) {
            TimeSheet(time: ClockTime(secondOfDay: at), title: "Evening check-in") { at = $0.secondOfDay; model.remindersChanged() }
        }
    }
}

/// Pro's app icons: the default and three alternates in the asset catalog.
enum AppIconChoice: String, CaseIterable {
    case paper = "Paper", night = "Night", mono = "Mono", dots = "Dots"
    var name: String { rawValue }
    /// The alternate icon's asset name; nil is the default icon.
    var asset: String? { self == .paper ? nil : "AppIcon-\(rawValue)" }
    static var current: AppIconChoice { allCases.first { $0.asset == UIApplication.shared.alternateIconName } ?? .paper }
}

private struct IconPage: View {
    @Environment(\.palette) private var palette
    @State private var current = AppIconChoice.current
    var body: some View {
        Page {
            HStack(spacing: 0) {
                ForEach(AppIconChoice.allCases, id: \.self) { icon in
                    let on = icon == current
                    Button {
                        guard !on else { return }
                        UIApplication.shared.setAlternateIconName(icon.asset) { _ in current = AppIconChoice.current }
                    } label: {
                        VStack(spacing: 6) {
                            Image("IconPreview-\(icon.name)").resizable().frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .stroke(on ? palette.ink : palette.hairline, lineWidth: on ? 2 : 1))
                            Text(icon.name).font(Type.labelMedium)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(icon.name + (on ? ", selected" : ""))
                }
            }
            .padding(.vertical, 8)
        }
        .navigationTitle("App icon")
    }
}
