import SwiftUI
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
    @State private var picks: [Template] = [] // ready-made or typed in, in tap order
    @State private var importing = false
    @State private var failed = false
    @State private var returning = false
    /// The first pick, checked on step 3; written as the first entry when onboarding ends.
    @State private var firstDone = false
    /// The reminder picked on step 4, if any; applied to every habit.
    @State private var reminder: ClockTime? = nil
    private let steps = 4

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
                case 2: FirstDot(template: picks.first ?? Template.all[0], done: $firstDone).transition(slide)
                default: WidgetsStep(picked: picks, reminder: $reminder).transition(slide)
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.easeOut(duration: 0.34), value: step)

            Button {
                if step == 2 && !firstDone { firstDone = true }
                else if step < steps - 1 { forward = true; step += 1 } else { finish() }
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
                case 2: Button("Not yet, it's day one") { firstDone = false; forward = true; step += 1 }
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
                picks = args.dropFirst(i + 2).prefix { Int($0) != nil }.compactMap { Int($0) }.map { Template.all[$0] }
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
        case 2: firstDone ? "Next" : "Done it today"
        default: "Start"
        }
    }

    private func finish() {
        let chosen = picks
        let store = model.store, today = model.today, done = firstDone, reminder = reminder
        _Concurrency.Task {
            for (order, tpl) in chosen.enumerated() {
                var t = Tracker(name: "", icon: "")
                tpl.apply(to: &t)
                t.sortOrder = order
                t.reminder = reminder
                let saved = try? await store.save(t)
                // The dot checked on step 3 is the first entry: the home screen opens at 1/N, not 0/N.
                if order == 0, done, let saved { try? await store.quick(saved, on: today) }
            }
        }
        // The 21:00 default is kept without a tap; ask here so it isn't saved silently with no permission.
        if reminder != nil { Reminders.askPermission() }
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
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.4), value: streak)
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
            // Today's dot pops when the check lands: the wall is where a check goes.
            FitHeatmap(data: Dictionary(uniqueKeysWithValues: demo.done.map { ($0, 1.0) }), today: today,
                       targetCell: compact ? 7 : 9, todayValue: check, popToday: check >= 1)
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
    @Binding var picks: [Template]
    @Environment(\.palette) private var palette
    @State private var adding = false
    @State private var own = ""
    @FocusState private var typing: Bool
    private let today = Day.today
    // ponytail: the free limit holds here without a word about it; the hint asks for fewer anyway.
    private var room: Bool { picks.count < Store.freeHabits || Store.shared.active }

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
                        Deck(cards: picks.suffix(4).map { DemoHabit(name: $0.name, icon: $0.icon) },
                             fanned: picks.count > 1, today: today, width: 250, compact: true)
                            .frame(maxHeight: .infinity)
                    }
                    Text("Fewer is easier to keep.")
                        .font(Type.bodyMedium).foregroundStyle(palette.dim)
                        .opacity(picks.count > 3 ? 1 : 0)
                        .animation(.easeOut(duration: 0.22), value: picks.count > 3)
                }
                .frame(height: 230)
                FlowLayout(spacing: 8) {
                    // Your own first, seen without scrolling; then any typed in (they show picked;
                    // a tap takes one back out), then the ready-made ones.
                    if adding {
                        TextField("Name your habit", text: $own)
                            .font(Type.bodyMedium).foregroundStyle(palette.ink)
                            .focused($typing).submitLabel(.done)
                            .onSubmit(addOwn)
                            .onChange(of: typing) { _, now in if !now { addOwn() } }
                            .frame(minWidth: 160, maxWidth: 260)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .overlay(Capsule().stroke(palette.ink, lineWidth: 1.5))
                            .onAppear { typing = true }
                    } else {
                        chip("Your own", icon: "Icons/ui-plus", on: false) { own = ""; adding = true }
                    }
                    ForEach(picks.filter { !Template.all.contains($0) } + Template.all, id: \.name) { t in
                        let on = picks.contains(t)
                        chip(t.name, icon: "Icons/\(t.icon)", on: on) {
                            if on { picks.removeAll { $0 == t } } else if room { picks.append(t) }
                        }
                    }
                }
                .padding(.vertical, 16)
                // Room under the last row, so every chip can scroll above the button.
                .padding(.bottom, 80)
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func chip(_ name: String, icon: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if icon != "Icons/" { Image(icon).resizable().frame(width: 18, height: 18) }
                Text(name).font(Type.bodyMedium)
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

    private func addOwn() {
        guard adding else { return }
        adding = false
        let name = own.trimmingCharacters(in: .whitespaces).prefix(40)
        guard !name.isEmpty, room, !picks.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        picks.append(Template.all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } ?? Template(name: String(name), icon: ""))
    }
}

// ---- Step 3: your first habit, for real; the box is yours to tap. ----

private struct FirstDot: View {
    let template: Template
    @Binding var done: Bool
    @Environment(Confetti.self) private var confetti
    @Environment(\.palette) private var palette
    @State private var check = 0.0
    @State private var ripple = false
    private let today = Day.today

    var body: some View {
        VStack(spacing: 0) {
            // A "No …" habit or one typed in reads "No sugar today?", "Gym today?".
            Title(title: template.name.hasPrefix("No ") || !Template.all.contains(template) ? "\(template.name) today?" : "Did you \(template.name.prefix(1).lowercased() + template.name.dropFirst()) today?",
                  text: done ? "That's your first dot. Tomorrow makes two." : "Tap the box if you have. If not, that's fine: it's day one.")
            ZStack {
                DemoCard(demo: DemoHabit(name: template.name, icon: template.icon), today: today, check: check,
                         onCheck: check < 1 ? { at in tap(at) } : nil)
                    .frame(width: 300)
                // The first dot lands as a ripple across the empty wall: one wave out from today.
                if ripple {
                    Circle().stroke(palette.ink.opacity(0.35), lineWidth: 2).frame(width: 40, height: 40)
                        .scaleEffect(3.2).opacity(0).offset(x: 110, y: 70)
                        .animation(.easeOut(duration: 0.7), value: ripple)
                }
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 4) {
                Image("Icons/ui-fire-fill").resizable().frame(width: 16, height: 16)
                Text("1 day streak").font(Type.titleSmall)
            }
                .foregroundStyle(palette.ink)
                .opacity(done ? 1 : 0).offset(y: done ? 0 : 12)
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: done)
                .padding(.bottom, 16)
        }
        .onAppear { if done { check = 1 } }
        // "Done it today" checks it from the button.
        .onChange(of: done) { _, now in
            guard now, check < 1 else { return }
            withAnimation(.linear(duration: 0.48)) { check = 1 }
            ripple = true
        }
    }

    private func tap(_ at: CGPoint) {
        Celebrate(confetti: confetti)(at: at)
        withAnimation(.linear(duration: 0.48)) { check = 1 }
        ripple = true
        done = true
    }
}

// ---- Step 4: the widgets, on a home screen, with your habits in them; then a reminder. ----

private struct WidgetsStep: View {
    let picked: [Template]
    @Binding var reminder: ClockTime?
    @Environment(Confetti.self) private var confetti
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @State private var risen = [false, false, false]
    @State private var checks = [0.0, 0.0, 0.0]
    @State private var water = 0.0 // progress toward 3 of 3
    @State private var askReminder = false
    private let today = Day.today
    private let times: [(String, ClockTime?)] = [("08:00", ClockTime(8, 0)), ("21:00", ClockTime(21, 0)), ("Never", nil)]

    /// Your picks first, topped up with examples; water is the long row, done three times a day.
    private var rows: [(String, String)] {
        var seen = Set<String>()
        return (picked.map { ($0.name, $0.icon) } + DemoHabit.samples.map { ($0.0, $0.1) })
            .filter { $0.0 != "Drink water" && seen.insert($0.0).inserted }
            .prefix(2).map { $0 }
    }

    var body: some View {
        let p = WidgetPalette.resolve(.auto, darkText: false, scheme: scheme)
        ScrollView {
            VStack(spacing: 0) {
                Title(title: "On your home screen", text: "No need to open the app.")
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        ForEach(0..<2, id: \.self) { i in
                            SmallWidgetMock(name: rows[i].0, icon: rows[i].1, seed: UInt64(i + 1), today: today, check: checks[i], p: p) { at in fire(at, i) }
                                .rising(risen[min(i, 1)])
                        }
                    }
                    ChecklistMock(rows: rows, today: today, checks: checks, water: water, p: p).rising(risen[2])
                }
                .padding(14)
                .background(LinearGradient(colors: [palette.ink.opacity(0.08), palette.ink.opacity(0.26)], startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                Text("Touch and hold your home screen, tap +, and find HabitDots.")
                    .font(Type.bodySmall).foregroundStyle(palette.dim).multilineTextAlignment(.center)
                    .padding(.top, 16)
                // Once the widgets have checked themselves off: one reminder a day, and the system asks right after a time is picked.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Remind me at").font(Type.labelLarge)
                    HStack(spacing: 8) {
                        ForEach(times, id: \.0) { t in
                            let on = reminder == t.1 && (t.1 != nil || askReminder)
                            Button {
                                reminder = t.1
                                if t.1 != nil { Reminders.askPermission() }
                            } label: {
                                Text(t.0).font(Type.labelLarge).frame(maxWidth: .infinity).frame(height: 40)
                                    .foregroundStyle(on ? palette.onInk : palette.ink)
                                    .background(on ? palette.ink : palette.background, in: Capsule())
                                    .overlay(Capsule().stroke(on ? .clear : palette.softBorder, lineWidth: 1))
                            }
                            .buttonStyle(Bouncy(scale: 0.95))
                        }
                    }
                }
                .padding(.top, 20)
                .opacity(askReminder ? 1 : 0).offset(y: askReminder ? 0 : 24)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: askReminder)
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
        await wait(600)
        askReminder = true
        if reminder == nil && !didSkipReminder { reminder = ClockTime(21, 0) }
    }
    private var didSkipReminder: Bool { false }
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
    let p: WidgetPalette
    let onCheck: (CGPoint) -> Void
    var body: some View {
        let done = DemoHabit.doneDays(seed: seed, today: today, streak: 6)
        var data = Dictionary(uniqueKeysWithValues: done.map { ($0, 1.0) })
        let _ = { data[today] = check }()
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(name).font(p.font(12, .bold)).lineLimit(2)
                Spacer(minLength: 4)
                WidgetCheck(done: check >= 1, partial: check < 1 ? check : 0, tick: p.tick).frame(width: 26, height: 26)
            }
            Spacer(minLength: 0)
            WidgetDots(data: data, today: today, shape: p.dots, maxCell: 9, ink: p.ink)
        }
        .padding(12)
        .foregroundStyle(p.text)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(p.background, in: RoundedRectangle(cornerRadius: p.receipt ? 4 : 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: p.receipt ? 4 : 22, style: .continuous).stroke(p.outlineCard ? p.text : .clear, lineWidth: 1))
    }
}

/// The checklist widget: today's habits as rows.
private struct ChecklistMock: View {
    let rows: [(String, String)]
    let today: Day
    let checks: [Double]
    let water: Double
    let p: WidgetPalette
    var body: some View {
        let done = checks.prefix(2).filter { $0 >= 1 }.count + (water >= 1 ? 1 : 0)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today").font(p.font(16, .bold))
                Spacer()
                Text("\(done)/3").font(p.font(13, .bold)).foregroundStyle(p.dim).contentTransition(.numericText())
            }
            row("Drink water", "drop", t: water >= 1 ? 1 : 0, partial: water < 1 ? water : 0, extra: "\(Int((water * 3).rounded()))/3")
            ForEach(0..<2, id: \.self) { i in row(rows[i].0, rows[i].1, t: checks[i], partial: 0, extra: nil) }
        }
        .padding(14)
        .foregroundStyle(p.text)
        .background(p.background, in: RoundedRectangle(cornerRadius: p.receipt ? 4 : 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: p.receipt ? 4 : 22, style: .continuous).stroke(p.outlineCard ? p.text : .clear, lineWidth: 1))
        .animation(.default, value: done)
    }

    private func row(_ name: String, _ icon: String, t: Double, partial: Double, extra: String?) -> some View {
        HStack(spacing: 10) {
            Image("Icons/\(icon)").resizable().frame(width: 17, height: 17).frame(width: 30, height: 30)
                .background(p.tile, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(name).font(p.font(14)).lineLimit(1)
            if let extra { Text(extra).font(p.font(12)).foregroundStyle(p.dim) }
            Spacer()
            WidgetCheck(done: t >= 1, partial: partial, tick: p.tick).frame(width: 28, height: 28)
        }
    }
}

/// A new phone: sign in and the account's habits come down (with Pro), or bring a backup file along.
private struct Returning: View {
    let onBackup: () -> Void
    let onSignedIn: () -> Void
    @Environment(\.palette) private var palette
    @State private var sync = Sync.shared
    @State private var busy = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Welcome back").font(Type.headlineSmall)
            Text("Sign in to the account you sync with, or restore a backup file from your other phone.")
                .font(Type.bodyMedium).foregroundStyle(palette.dim).padding(.bottom, 8)
            // Straight to Google sign-in, no paywall: a returning Pro user's purchase comes back from
            // the App Store by itself and the habits follow (sync is Pro).
            if sync.available {
                RowGroup { Row(label: "Sign in with Google", icon: "ui-cloud", chevron: false) { signIn { try await sync.signInWithGoogle() } } }
            }
            RowGroup { Row(label: "Restore a backup file", icon: "ui-database", chevron: false, action: onBackup) }
            if busy { ProgressView().frame(maxWidth: .infinity) }
        }
        .padding(.horizontal, 20).padding(.top, 28)
        .frame(maxHeight: .infinity, alignment: .top)
        .disabled(busy)
        .presentationDetents([.height(sync.available ? 360 : 290)])
        .textCap()
        .presentationCornerRadius(Radius.sheet)
        .presentationBackground(palette.background)
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
