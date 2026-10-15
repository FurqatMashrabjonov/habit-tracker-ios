import SwiftUI
import AuthenticationServices
import UniformTypeIdentifiers
import HabitData
import HabitDesign
import HabitDomain

/// Shown once, on a fresh install: the idea, a few habits, then the widgets. Same steps and words as Android.
struct OnboardingView: View {
    let onDone: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var step = 0
    @State private var forward = true
    @State private var picks: [Int] = [] // indexes into Template.all, in tap order
    @State private var importing = false
    @State private var failed = false
    @State private var returning = false
    private let steps = 3

    var body: some View {
        VStack(spacing: 0) {
            // Where you are, in the app's own unit: dots.
            HStack(spacing: 6) {
                ForEach(0..<steps, id: \.self) { i in
                    Capsule().fill(palette.ink.opacity(i <= step ? 1 : 0.15)).frame(width: i == step ? 22 : 8, height: 8)
                }
                Spacer()
            }
            .frame(height: 56)
            .animation(.easeOut(duration: 0.26), value: step)

            ZStack {
                switch step {
                case 0: Hero().transition(slide)
                case 1: PickHabits(picks: $picks).transition(slide)
                default: WidgetsStep(picked: picks.map { Template.all[$0] }).transition(slide)
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.easeOut(duration: 0.34), value: step)

            Button {
                if step < steps - 1 { forward = true; step += 1 } else { finish() }
            } label: {
                Text(buttonLabel).font(Type.titleSmall).contentTransition(.opacity)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .foregroundStyle(canGo ? palette.onInk : palette.dim)
                    .background(canGo ? palette.ink : palette.tileHigh, in: Capsule())
            }
            .disabled(!canGo)
            .buttonStyle(Bouncy(scale: 0.97))
            .animation(.easeOut(duration: 0.2), value: buttonLabel)

            // A second way forward; a fixed-height slot so the main button doesn't jump.
            ZStack {
                switch step {
                case 0: Button("I already use HabitDots") { returning = true }
                case 1: Button("Start empty") { picks = []; finish() }
                default: EmptyView()
                }
            }
            .font(Type.labelLarge).foregroundStyle(palette.dim)
            .frame(height: 52)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .background(palette.background)
        .gesture(DragGesture().onEnded { g in if g.translation.width > 80 && step > 0 { forward = false; step -= 1 } })
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .item]) { result in
            // Coming from the Android app (or another iPhone): a backup file brings every habit along.
            guard case .success(let picked) = result else { return }
            let ok = picked.startAccessingSecurityScopedResource()
            defer { if ok { picked.stopAccessingSecurityScopedResource() } }
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("restore-\(UUID().uuidString).db")
            do {
                try FileManager.default.copyItem(at: picked, to: copy)
                try model.restore(from: copy)
                picks = []
                finish()
            } catch { failed = true }
        }
        .alert("Not a valid backup file", isPresented: $failed) { Button("OK") {} }
        .sheet(isPresented: $returning) {
            Returning(onBackup: { returning = false; importing = true }, onSignedIn: { returning = false; picks = []; finish() })
        }
        #if DEBUG
        .onAppear {
            // `-onb <step> [picks…]` opens a later step, to check it without tapping through.
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-onb"), i + 1 < args.count, let n = Int(args[i + 1]) {
                step = n
                picks = args.dropFirst(i + 2).prefix { Int($0) != nil }.compactMap { Int($0) }
            }
            if args.contains("-returning") { returning = true }
        }
        #endif
    }

    private var slide: AnyTransition {
        let dir: CGFloat = forward ? 1 : -1
        return .asymmetric(insertion: .offset(x: 80 * dir).combined(with: .opacity), removal: .offset(x: -80 * dir).combined(with: .opacity))
    }

    private var canGo: Bool { step != 1 || !picks.isEmpty }

    private var buttonLabel: String {
        switch step {
        case 0: "Get started"
        case 1: picks.isEmpty ? "Pick at least one" : "Continue"
        default: "Start"
        }
    }

    private func finish() {
        let chosen = picks.map { Template.all[$0] }
        let store = model.store
        _Concurrency.Task {
            for (order, tpl) in chosen.enumerated() {
                var t = Tracker(name: "", icon: "")
                tpl.apply(to: &t)
                t.sortOrder = order
                try? await store.save(t)
            }
        }
        UserDefaults.standard.set(true, forKey: "onboarded")
        onDone()
    }
}

private struct Title: View {
    let title: String
    var text: String? = nil
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Type.headlineMedium)
            if let text { Text(text).font(Type.bodyLarge).foregroundStyle(palette.dim) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8).padding(.bottom, 24)
    }
}

// ---- Example habits ------------------------------------------------------------------------------

/// A habit as the onboarding draws it: name, icon and a year of history.
struct DemoHabit: Hashable {
    let name: String
    let icon: String
    var done: Set<Day> = []
    var doneToday = false

    static let samples: [(String, String, Bool)] = [
        ("Read 20 pages", "book-open", true), ("Drink water", "drop", true),
        ("Morning run", "person-simple-run", false), ("Meditate", "flower-lotus", false),
    ]

    /// A year of done days that gets denser toward today, like a habit that stuck, with the last
    /// `streak` days all done. ponytail: a fixed seed per habit, so it looks the same every time.
    static func doneDays(seed: UInt64, today: Day, streak: Int) -> Set<Day> {
        var state = seed &* 0x9E3779B97F4A7C15
        func next() -> Double { state = state &* 6364136223846793005 &+ 1442695040888963407; return Double(state >> 11) / Double(1 << 53) }
        return Set((1...364).compactMap { ago in
            ago < streak || next() < 0.3 + 0.6 * (1 - Double(ago) / 364) ? today - ago : nil
        })
    }
}

/// Fires the burst and the done haptic from a point on screen.
@MainActor
private struct Celebrate {
    let confetti: Confetti
    func callAsFunction(at point: CGPoint) {
        confetti.fire(at: point)
        Haptics.done()
    }
}

private struct DemoCard: View {
    let demo: DemoHabit
    let today: Day
    var compact = false
    /// 0...1, today's check.
    var check: Double
    var onCheck: ((CGPoint) -> Void)? = nil
    @Environment(\.palette) private var palette
    @State private var pulse = false

    var body: some View {
        let done = demo.done.union(check >= 1 ? [today] : [])
        let streak = currentStreak(done, today: today)
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                HabitIconTile(icon: demo.icon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(demo.name).font(Type.titleSmall).lineLimit(1)
                    Group {
                        if streak > 0 { StreakLabel(days: streak) } else { Text("Day one") }
                    }
                    .font(Type.bodySmall).foregroundStyle(palette.dim)
                }
                Spacer(minLength: 0)
                GeometryReader { geo in
                    CheckGlyph(t: check)
                        .scaleEffect(onCheck != nil && pulse ? 1.14 : 1)
                        .contentShape(Rectangle())
                        .onTapGesture { let f = geo.frame(in: .global); onCheck?(CGPoint(x: f.midX, y: f.midY)) }
                }
                .frame(width: 28, height: 28)
            }
            FitHeatmap(data: Dictionary(uniqueKeysWithValues: demo.done.map { ($0, 1.0) }), today: today,
                       targetCell: compact ? 7 : 9, todayValue: check)
        }
        .padding(14)
        .background(palette.surfaceLow, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).stroke(palette.softBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        .onAppear {
            // A gentle pulse while it waits for your tap.
            if onCheck != nil { withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) { pulse = true } }
        }
        .onChange(of: onCheck == nil) { _, waiting in if waiting { pulse = false } }
    }
}

/// Cards stacked (back cards peeking above) or spread like a hand of cards. `cards` go back to front;
/// a card that joins flies in from below.
private struct Deck: View {
    let cards: [DemoHabit]
    let fanned: Bool
    let today: Day
    var width: CGFloat = 260
    var compact = false
    var frontCheck: Double = 0
    var onFrontCheck: ((CGPoint) -> Void)? = nil

    var body: some View {
        ZStack {
            ForEach(Array(cards.enumerated()), id: \.element.name) { i, demo in
                let fromFront = cards.count - 1 - i
                let center = Double(cards.count - 1) / 2
                DemoCard(demo: demo, today: today, compact: compact,
                         check: fromFront == 0 ? frontCheck : (demo.doneToday ? 1 : 0),
                         onCheck: fromFront == 0 ? onFrontCheck : nil)
                    .frame(width: width)
                    .scaleEffect(fanned ? 0.94 : 1 - Double(fromFront) * 0.06)
                    // Fan around a point far below the cards, like a hand of playing cards.
                    .rotationEffect(.degrees(fanned ? (Double(i) - center) * 7 : 0), anchor: UnitPoint(x: 0.5, y: 2))
                    .offset(y: fanned ? 0 : -CGFloat(fromFront) * 20)
                    .zIndex(Double(i))
                    .transition(.asymmetric(insertion: .offset(y: 700).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.72), value: fanned)
        .animation(.spring(response: 0.55, dampingFraction: 0.7), value: cards.map(\.name))
    }
}

// ---- Step 1: a deck of habit cards flies in and fans out; you check the front one. ----

private struct Hero: View {
    @Environment(Confetti.self) private var confetti
    @Environment(\.palette) private var palette
    @State private var shown = 0
    @State private var fanned = false
    @State private var check = 0.0
    private let today = Day.today
    private let demos: [DemoHabit] = DemoHabit.samples.enumerated().map { i, s in
        DemoHabit(name: s.0, icon: s.1, done: DemoHabit.doneDays(seed: UInt64(i + 1), today: .today, streak: 4 + 5 * i), doneToday: s.2)
    }.reversed()

    var body: some View {
        VStack(spacing: 0) {
            Title(title: "Every day is a dot.", text: "Check it off. Watch the wall fill in.")
            Deck(cards: Array(demos.prefix(shown)), fanned: fanned, today: today, frontCheck: check,
                 onFrontCheck: fanned && check < 1 ? { at in
                     Celebrate(confetti: confetti)(at: at)
                     withAnimation(.linear(duration: 0.48)) { check = 1 }
                 } : nil)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { fanned.toggle() }
            Text(check >= 1 ? "That's one dot." : "Tap the box")
                .font(Type.titleSmall).foregroundStyle(palette.dim)
                .contentTransition(.opacity)
                .opacity(fanned ? 1 : 0)
                .animation(.easeOut(duration: 0.3), value: fanned)
                .animation(.easeOut(duration: 0.3), value: check >= 1)
                .padding(.bottom, 16)
        }
        .task {
            for _ in demos { try? await _Concurrency.Task.sleep(for: .milliseconds(160)); shown += 1 }
            try? await _Concurrency.Task.sleep(for: .milliseconds(700))
            fanned = true
        }
    }
}

// ---- Step 2: pick habits; each one joins a deck of your own. ----

private struct PickHabits: View {
    @Binding var picks: [Int]
    @Environment(\.palette) private var palette
    private var pro: Bool { Store.shared.active }
    private let today = Day.today

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Title(title: "Start small", text: "Pick a few. Add more any time.")
                ZStack(alignment: .bottom) {
                    if picks.isEmpty {
                        // An empty card slot: where your first habit will land.
                        Text("Select your habits").font(Type.bodyMedium).foregroundStyle(palette.dim)
                            .frame(width: 280, height: 150)
                            .background(palette.surfaceLow, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                            .frame(maxHeight: .infinity)
                    } else {
                        // ponytail: only the last four picks are drawn; more would hide behind them.
                        Deck(cards: picks.suffix(4).map { DemoHabit(name: Template.all[$0].name, icon: Template.all[$0].icon) },
                             fanned: picks.count > 1, today: today, width: 250, compact: true)
                            .frame(maxHeight: .infinity)
                    }
                    // Free covers five; the limit shows here, on day one, not as a surprise later.
                    Text(picks.count >= Store.freeHabits && !pro ? "\(Store.freeHabits) habits on the free plan" : "Fewer is easier to keep.")
                        .font(Type.bodyMedium).foregroundStyle(palette.dim)
                        .opacity(picks.count > 3 ? 1 : 0)
                        .animation(.easeOut(duration: 0.22), value: picks.count > 3)
                }
                .frame(height: 230)
                FlowLayout(spacing: 8) {
                    ForEach(Array(Template.all.enumerated()), id: \.offset) { i, t in
                        let on = picks.contains(i)
                        Button {
                            if on { picks.removeAll { $0 == i } }
                            else if picks.count < Store.freeHabits || pro { picks.append(i) }
                        } label: {
                            HStack(spacing: 6) {
                                Image("Icons/\(t.icon)").resizable().frame(width: 18, height: 18)
                                Text(t.name).font(Type.bodyMedium)
                            }
                            .foregroundStyle(on ? palette.onInk : palette.ink)
                            .padding(.leading, 12).padding(.trailing, 14).padding(.vertical, 10)
                            .background(on ? palette.ink : palette.background, in: Capsule())
                            .overlay(Capsule().stroke(on ? .clear : palette.softBorder, lineWidth: 1))
                            .animation(.easeOut(duration: 0.2), value: on)
                        }
                        .buttonStyle(Bouncy(scale: 0.95))
                        .sensoryFeedback(.selection, trigger: on)
                    }
                }
                .padding(.vertical, 16)
            }
        }
        .scrollIndicators(.hidden)
    }
}

// ---- Step 3: the widgets, on a home screen, with your habits in them. ----

private struct WidgetsStep: View {
    let picked: [Template]
    @Environment(Confetti.self) private var confetti
    @Environment(\.palette) private var palette
    @State private var risen = [false, false, false]
    @State private var checks = [0.0, 0.0, 0.0]
    @State private var water = 0.0 // progress toward 3 of 3
    private let today = Day.today

    /// Your picks first, topped up with examples; water is the long row, done three times a day.
    private var rows: [(String, String)] {
        var seen = Set<String>()
        return (picked.map { ($0.name, $0.icon) } + DemoHabit.samples.map { ($0.0, $0.1) })
            .filter { $0.0 != "Drink water" && seen.insert($0.0).inserted }
            .prefix(2).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Title(title: "On your home screen", text: "No need to open the app.")
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        ForEach(0..<2, id: \.self) { i in
                            SmallWidgetMock(name: rows[i].0, icon: rows[i].1, seed: UInt64(i + 1), today: today, check: checks[i]) { at in fire(at, i) }
                                .rising(risen[min(i, 1)])
                        }
                    }
                    ChecklistMock(rows: rows, today: today, checks: checks, water: water).rising(risen[2])
                }
                .padding(14)
                .background(LinearGradient(colors: [palette.ink.opacity(0.08), palette.ink.opacity(0.26)], startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                Text("Touch and hold your home screen, tap +, and find HabitDots.")
                    .font(Type.bodySmall).foregroundStyle(palette.dim).multilineTextAlignment(.center)
                    .padding(.top, 16)
            }
        }
        .scrollIndicators(.hidden)
        .task { await play() }
    }

    private func fire(_ at: CGPoint, _ i: Int) {
        Celebrate(confetti: confetti)(at: at)
        withAnimation(.linear(duration: 0.48)) { checks[i] = 1 }
    }

    /// Widgets rise into place one by one, then the two habits and the water get checked in turn.
    private func play() async {
        func wait(_ ms: Int) async { try? await _Concurrency.Task.sleep(for: .milliseconds(ms)) }
        for i in 0..<3 {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) { risen[i] = true }
            await wait(300)
        }
        await wait(900)
        withAnimation(.linear(duration: 0.48)) { checks[0] = 1 }
        Haptics.done()
        await wait(650)
        withAnimation(.linear(duration: 0.48)) { checks[1] = 1 }
        Haptics.done()
        // Water: two taps fill the box part way, the third completes it.
        for n in 1...2 {
            await wait(n == 1 ? 650 : 450)
            Haptics.tick()
            withAnimation(.easeInOut(duration: 0.26)) { water = Double(n) / 3 }
        }
        await wait(450)
        withAnimation(.linear(duration: 0.48)) { water = 1 }
        Haptics.done()
    }
}

private extension View {
    func rising(_ up: Bool) -> some View { offset(y: up ? 0 : 360).opacity(up ? 1 : 0) }
}

/// The single-habit widget: name, check, this month's dots.
private struct SmallWidgetMock: View {
    let name: String
    let icon: String
    let seed: UInt64
    let today: Day
    let check: Double
    let onCheck: (CGPoint) -> Void
    @Environment(\.palette) private var palette
    var body: some View {
        let done = DemoHabit.doneDays(seed: seed, today: today, streak: 6)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(name).font(Type.inter(12, .bold)).lineLimit(2)
                Spacer(minLength: 4)
                CheckGlyph(t: check).frame(width: 26, height: 26)
            }
            Spacer(minLength: 0)
            FitHeatmap(data: Dictionary(uniqueKeysWithValues: done.map { ($0, 1.0) }), today: today, targetCell: 9, todayValue: check)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(palette.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// The checklist widget: today's habits as rows.
private struct ChecklistMock: View {
    let rows: [(String, String)]
    let today: Day
    let checks: [Double]
    let water: Double
    @Environment(\.palette) private var palette
    var body: some View {
        let done = checks.prefix(2).filter { $0 >= 1 }.count + (water >= 1 ? 1 : 0)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today").font(Type.inter(16, .bold))
                Spacer()
                Text("\(done)/3").font(Type.inter(13, .bold)).foregroundStyle(palette.dim).contentTransition(.numericText())
            }
            row("Drink water", "drop", t: water >= 1 ? 1 : 0, partial: water < 1 ? water : 0, extra: "\(Int((water * 3).rounded()))/3")
            ForEach(0..<2, id: \.self) { i in row(rows[i].0, rows[i].1, t: checks[i], partial: 0, extra: nil) }
        }
        .padding(14)
        .background(palette.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(.default, value: done)
    }

    private func row(_ name: String, _ icon: String, t: Double, partial: Double, extra: String?) -> some View {
        HStack(spacing: 10) {
            HabitIconTile(icon: icon, size: 30)
            Text(name).font(Type.bodyMedium).lineLimit(1)
            if let extra { Text(extra).font(Type.bodySmall).foregroundStyle(palette.dim) }
            Spacer()
            CheckGlyph(t: t, partial: partial).frame(width: 28, height: 28)
        }
    }
}

/// A new phone: sign in and the account's habits come down (sync is Pro, so the paywall with
/// Restore purchase comes first for anyone without it), or bring a backup file along.
private struct Returning: View {
    let onBackup: () -> Void
    let onSignedIn: () -> Void
    @Environment(\.palette) private var palette
    @State private var store = Store.shared
    @State private var sync = Sync.shared
    @State private var busy = false
    @State private var paywall = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Welcome back").font(Type.headlineSmall)
            Text("Sign in to the account you sync with, or restore a backup file from your other phone.")
                .font(Type.bodyMedium).foregroundStyle(palette.dim).padding(.bottom, 8)
            if sync.available && store.active {
                SignInWithAppleButton(.signIn) { sync.prepareAppleRequest($0) } onCompletion: { result in
                    guard case .success(let auth) = result else { return }
                    signIn { try await sync.signInWithApple(auth) }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50).clipShape(Capsule())
                RowGroup { Row(label: "Sign in with Google", icon: "ui-cloud", chevron: false) { signIn { try await sync.signInWithGoogle() } } }
            } else if sync.available {
                RowGroup { Row(label: "Sync with your account", icon: "ui-cloud", value: "Pro") { paywall = true } }
            }
            RowGroup { Row(label: "Restore a backup file", icon: "ui-database", chevron: false, action: onBackup) }
            if busy { ProgressView().frame(maxWidth: .infinity) }
        }
        .padding(.horizontal, 20).padding(.top, 28)
        .frame(maxHeight: .infinity, alignment: .top)
        .disabled(busy)
        .presentationDetents([.height(sync.available && store.active ? 360 : 290)])
        .textCap()
        .presentationCornerRadius(Radius.sheet)
        .presentationBackground(palette.background)
        .sheet(isPresented: $paywall) { Paywall() }
        .alert("Couldn't sign in", isPresented: $failed) { Button("OK") {} }
    }

    private func signIn(_ work: @escaping () async throws -> Void) {
        busy = true
        _Concurrency.Task {
            do { try await work(); onSignedIn() } catch { failed = true }
            busy = false
        }
    }
}
