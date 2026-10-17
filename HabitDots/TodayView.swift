import Foundation
import SwiftUI
import HabitData
import HabitDesign
import HabitDomain

/// HabitKit-like home, as on Android: round buttons on top (settings | stats, add), the page title,
/// habit cards, and a floating glass pill at the bottom that switches between Habits and the Inbox.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var inbox = false
    @State private var adding = false
    @State private var taskSheet: Task?
    @State private var settings = false
    @State private var path: [Int64] = []
    @State private var stats = false
    // From a card's long-press menu.
    @State private var editHabit: Tracker?
    @State private var shareHabit: Tracker?
    @State private var noteHabit: Tracker?
    @State private var deleteHabit: Tracker?
    /// Ids top to bottom while a card is dragged; saved on drop.
    @State private var order: [Int64]?
    @State private var dragged: Int64?
    @Namespace private var zoom

    var body: some View {
        NavigationStack(path: $path) {
            home
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: $stats) { StatsView() }
                .navigationDestination(for: Int64.self) { id in
                    DetailView(id: id, store: model.store, today: model.today)
                        .navigationTransition(.zoom(sourceID: id, in: zoom))
                }
        }
        .onOpenURL { url in
            // From widgets: habitdots://habit/<id>, habitdots://inbox, habitdots://add-task, habitdots://habits.
            switch url.host() {
            case "habit": if let id = Int64(url.lastPathComponent) { inbox = false; path = [id] }
            case "inbox": path = []; inbox = true
            case "habits": path = []; inbox = false
            case "add-task": path = []; inbox = true; var t = Task(title: ""); t.dueDate = model.today; taskSheet = t
            default: break
            }
        }
        .onChange(of: model.openHabit) { _, id in
            guard let id else { return }
            path = [id]
            model.openHabit = nil
        }
        .onAppear {
            // `-open <id>` opens a habit's page on launch (screenshots, deep links later).
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-open"), i + 1 < args.count, let id = Int64(args[i + 1]) { path = [id] }
            if args.contains("-add") { adding = true }
            if args.contains("-inbox") { inbox = true }
            if args.contains("-settings") { settings = true }
            if args.contains("-stats") { stats = true }
            #if DEBUG
            // `-restore <path>` runs a restore on launch, to check it without tapping through Settings.
            if let i = args.firstIndex(of: "-restore"), i + 1 < args.count { try? model.restore(from: URL(fileURLWithPath: args[i + 1])) }
            if args.contains("-snack") { model.snack = .init(text: "“Read 10 pages” deleted") {} }
            #endif
        }
    }

    private var home: some View {
        VStack(spacing: 0) {
            header
            // Habits and the Inbox sit side by side and page like Telegram's tabs: a swipe drags the
            // next page in attached to the one leaving, and the pill scrolls there.
            GeometryReader { geo in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        habits.frame(width: geo.size.width).id(0)
                        InboxView { taskSheet = $0 }.frame(width: geo.size.width).id(1)
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                .scrollPosition(id: Binding<Int?>(get: { inbox ? 1 : 0 }, set: { if let v = $0 { inbox = v == 1 } }))
                .animation(.spring(response: 0.38, dampingFraction: 0.86), value: inbox)
            }
        }
        .background(palette.background)
        .overlay(alignment: .bottom) { Pill(inbox: $inbox).padding(.bottom, 8) }
        .overlay(alignment: .bottom) {
            if let snack = model.snack {
                SnackBar(text: snack.text, onUndo: snack.undo.map { undo in { undo(); model.snack = nil } })
                    .padding(.bottom, 76)
                    .id(snack.id)
                    .task { try? await _Concurrency.Task.sleep(for: .seconds(5)); if model.snack?.id == snack.id { model.snack = nil } }
            }
        }
        .animation(.snappy, value: model.snack?.id)
        .sheet(isPresented: $adding) { EditSheet(existing: nil) }
        .sheet(item: $editHabit) { EditSheet(existing: $0) }
        .sheet(item: $shareHabit) { ShareHabitSheet(tracker: $0) }
        .sheet(item: $noteHabit) { t in
            NoteSheet(title: "\(t.name) · \(Words.date(model.today))", initial: "") { model.saveNote($0, of: t, on: model.today) }
        }
        .confirmationDialog("Delete habit", isPresented: Binding(get: { deleteHabit != nil }, set: { if !$0 { deleteHabit = nil } }),
                            titleVisibility: .visible, presenting: deleteHabit) { t in
            Button("Delete", role: .destructive) { model.delete(t) }
        } message: { t in
            Text("“\(t.name)” and its whole history are removed from every phone. You can restore it from Settings › Recently deleted for 30 days.")
        }
        .sheet(isPresented: $settings) { SettingsSheet { id in path.append(id) } }
        .sheet(item: $taskSheet) { task in
            TaskSheet(initial: task, today: model.today, onSave: { model.save($0) },
                      onDelete: task.id == nil ? nil : { model.delete(task) })
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                RoundIconButton(icon: "ui-gear-six", label: "Settings") { settings = true }
                Spacer()
                RoundIconButton(icon: "ui-chart-bar", label: "Statistics") { stats = true }
                AddButton(label: inbox ? "New task" : "New habit") {
                    if inbox { var t = Task(title: ""); t.dueDate = model.today; taskSheet = t }
                    // A new habit past the free limit opens the paywall instead of the editor.
                    else if Store.shared.canAddHabit(activeHabits: model.rows?.count ?? 0) || Store.shared.require() { adding = true }
                }
            }
            .padding(.vertical, 8)
            HStack(spacing: 6) {
                Text(inbox ? "Inbox" : "Habits")
                    .font(Type.titleLarge)
                    .contentTransition(.opacity)
                Spacer()
                // How the cards look sits by the list it changes, not three taps away in Settings.
                if !inbox { CardStyleButton(sample: sorted.first, second: sorted.dropFirst().first).transition(.opacity) }
            }
            .frame(height: 48)
            .animation(.easeOut(duration: 0.22), value: inbox)
        }
        .padding(.horizontal, 16)
    }

    @AppStorage("cards") private var cardStyle = CardStyle.wall

    private var habits: some View {
        let tiled = cardStyle.tiled && Store.shared.active
        return ScrollView {
            // Rings sit two to a row; every other style is one card per row.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: tiled ? 2 : 1), spacing: 12) {
                if let rows = model.rows, rows.isEmpty { EmptyHabits { adding = true } }
                ForEach(sorted) { row in
                    HabitCard(row: row, today: model.today) { model.toggle(row.tracker) }
                        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                        .onTapGesture { path.append(row.id) }
                        .contextMenu { menu(row) }
                        // VoiceOver: one element per card; activating opens it, the Check action marks today.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(row.tracker.name), \(row.streak) day streak")
                        .accessibilityValue(row.progress(on: model.today) >= 1 ? "Done today"
                                            : row.tracker.target > 1 ? "\(row.todayCount) of \(row.tracker.target) today" : "Not done today")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { path.append(row.id) }
                        .accessibilityAction(named: "Check") { model.toggle(row.tracker) }
                        // Long-press and move: the card lifts and the others make room, as on Android.
                        .onDrag {
                            dragged = row.id
                            order = sorted.map(\.id)
                            return NSItemProvider(object: "\(row.id)" as NSString)
                        }
                        .onDrop(of: [.text], delegate: Reorder(target: row.id, dragged: $dragged, order: $order) { model.reorder($0) })
                        .opacity(dragged == row.id ? 0.4 : 1)
                        .matchedTransitionSource(id: row.id, in: zoom) { $0.clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)) }
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 96)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: sorted.map(\.id))
        }
        .scrollIndicators(.hidden)
        // A card let go between cards (not on one) still keeps its new place.
        // ponytail: one let go outside the list stays faded until the next drag; a drop there is rare.
        .onDrop(of: [.text], delegate: Reorder(target: -1, dragged: $dragged, order: $order) { model.reorder($0) })
    }

    /// The rows, in the dragged order while a card moves.
    private var sorted: [HabitRow] {
        let rows = model.rows ?? []
        guard let order else { return rows }
        return rows.sorted { (order.firstIndex(of: $0.id) ?? .max) < (order.firstIndex(of: $1.id) ?? .max) }
    }

    @ViewBuilder
    private func menu(_ row: HabitRow) -> some View {
        let yesterday = model.today - 1
        // Only to catch up on a missed day; a wrong mark is undone from the habit's calendar.
        if row.progress(on: yesterday) < 1 {
            Button { model.toggle(row.tracker, on: yesterday) } label: { Label("Complete yesterday", image: "Icons/ui-calendar-check-line") }
        }
        // Sick or away: today becomes a rest day the streak steps over (again to undo).
        if row.progress(on: model.today) < 1 {
            Button { model.toggleRest(row.tracker) } label: { Label(row.resting ? "Undo rest day" : "Rest day", image: "Icons/moon") }
        }
        Button { noteHabit = row.tracker } label: { Label("Add note", image: "Icons/ui-note-pencil-line") }
        Button { editHabit = row.tracker } label: { Label("Edit", image: "Icons/ui-pencil-simple") }
        Button { shareHabit = row.tracker } label: { Label("Share", image: "Icons/ui-share-network") }
        Button { model.archive(row.tracker) } label: { Label("Archive", image: "Icons/ui-archive") }
        Button(role: .destructive) { deleteHabit = row.tracker } label: { Label("Delete", image: "Icons/ui-trash") }
    }
}

extension Tracker: @retroactive Identifiable {}

/// Moves the dragged card to where it hovers; the new order is saved on drop.
private struct Reorder: DropDelegate {
    let target: Int64
    @Binding var dragged: Int64?
    @Binding var order: [Int64]?
    let onDone: ([Int64]) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != target, var o = order,
              let from = o.firstIndex(of: dragged), let to = o.firstIndex(of: target) else { return }
        o.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
        withAnimation(.snappy) { order = o }
        Haptics.tick()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        if let order { onDone(order) }
        dragged = nil
        // The saved order comes back through the live query; until then keep showing this one.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { order = nil }
        return true
    }
}

/// "Task done · Undo" over the bottom pill.
struct SnackBar: View {
    let text: String
    var onUndo: (() -> Void)?
    @Environment(\.palette) private var palette
    var body: some View {
        HStack(spacing: 16) {
            Text(text).font(Type.bodyMedium).lineLimit(onUndo == nil ? 2 : 1)
            Spacer(minLength: 0)
            if let onUndo { Button("Undo", action: onUndo).font(Type.labelLarge) }
        }
        .foregroundStyle(palette.onInk)
        .padding(.leading, 18).padding(.trailing, 14).padding(.vertical, 14)
        .background(palette.ink, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
        .padding(.horizontal, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private extension AnyTransition {
    /// Slides a sixth of the width and fades, like the Android page switch.
    static func slide(_ dir: CGFloat) -> AnyTransition {
        .asymmetric(insertion: .modifier(active: Shift(x: dir), identity: Shift(x: 0)).combined(with: .opacity),
                    removal: .modifier(active: Shift(x: -dir), identity: Shift(x: 0)).combined(with: .opacity))
    }
}

private struct Shift: ViewModifier {
    let x: CGFloat
    func body(content: Content) -> some View {
        content.visualEffect { v, proxy in v.offset(x: x * proxy.size.width / 6) }
    }
}

/// Name, streak, check; underneath, the habit's history as a dot grid filling the card width.
struct HabitCard: View {
    let row: HabitRow
    let today: Day
    /// A fixed look (the style picker's previews); nil draws the chosen one.
    var style: CardStyle? = nil
    let onToggle: () -> Void
    @Environment(\.palette) private var palette
    @Environment(Confetti.self) private var confetti
    @State private var todayCell: Double = 0
    @AppStorage("cards") private var cards = CardStyle.wall
    private var pro: Bool { Store.shared.active }

    /// Done days among the strip's seven, for "4/7 this week".
    private var weekDone: Int { (0..<7).filter { row.progress(on: today - $0) >= 1 }.count }

    /// Done days this month over the days gone, for "14/17 in October".
    private var monthDone: (done: Int, gone: Int) {
        let first = today.withDay(1)
        return ((0...(today - first)).filter { row.progress(on: first + $0) >= 1 }.count, today - first + 1)
    }

    var body: some View {
        let shown = style ?? (pro ? cards : .wall)
        Group {
            if shown.tiled { tile } else { card(shown) }
        }
        .background(palette.surfaceLow, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).stroke(palette.softBorder, lineWidth: 1))
        // Raw value: a rest day's -1 draws the dash.
        .onAppear { todayCell = row.progress[today] ?? 0 }
        .onChange(of: row.progress[today] ?? 0) { _, v in withAnimation(.easeInOut(duration: 0.45)) { todayCell = v } }
    }

    /// Two to a row: icon and a ring around the check, then name and streak. The ring is the last
    /// 30 days; a counted habit's ring is today's count instead, since that is what the tap fills.
    private var tile: some View {
        let t = row.tracker
        let done = row.progress(on: today) >= 1
        let counted = t.target > 1
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HabitIconTile(icon: t.icon, size: 40)
                Spacer(minLength: 0)
                GeometryReader { geo in
                    ZStack {
                        Circle().stroke(palette.tint, lineWidth: 4)
                        Circle().trim(from: 0, to: counted ? min(Double(row.todayCount) / Double(t.target), 1) : row.momentum)
                            .stroke(palette.ink, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.spring(response: 0.6, dampingFraction: 0.85), value: counted ? Double(row.todayCount) : row.momentum)
                        CheckButton(done: done, count: row.todayCount, target: t.target, size: 26) {
                            if !done && row.todayCount + 1 >= t.target {
                                let f = geo.frame(in: .global)
                                confetti.fire(at: CGPoint(x: f.midX, y: f.midY))
                            }
                            onToggle()
                        }
                    }
                }
                .frame(width: 46, height: 46)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(t.name).font(Type.titleSmall).lineLimit(1)
                HStack(spacing: 0) {
                    if row.mustNotMiss { Text("Don't miss today!") } else { StreakLabel(days: row.streak) }
                    if counted { Text("  ·  \(min(row.todayCount, t.target))/\(t.target)") }
                    else { Text("  ·  \(Int((row.momentum * 100).rounded()))%") }
                }
                .lineLimit(1)
                .font(Type.bodySmall)
                .foregroundStyle(palette.dim)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card(_ shown: CardStyle) -> some View {
        let t = row.tracker
        let done = row.progress(on: today) >= 1
        return VStack(spacing: 14) {
            HStack(spacing: 12) {
                HabitIconTile(icon: t.icon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.name).font(Type.titleSmall).lineLimit(1)
                    HStack(spacing: 0) {
                        if row.mustNotMiss {
                            Text("Don't miss today!").fixedSize()
                        } else {
                            StreakLabel(days: row.streak).fixedSize()
                        }
                        if t.target > 1 { Text("  ·  \(min(row.todayCount, t.target))/\(t.target)").fixedSize() }
                        // The period count only where it reads as one number (a counted habit already shows x/N).
                        else if shown == .compact { Text("  ·  \(weekDone)/7 this week").fixedSize() }
                        else if shown == .month { let m = monthDone; Text("  ·  \(m.done)/\(m.gone) in \(Words.months[today.month - 1])").fixedSize() }
                        if let cue = t.cue, !cue.isEmpty { Text("  ·  \(cue)") }
                    }
                    .lineLimit(1)
                    .font(Type.bodySmall)
                    .foregroundStyle(palette.dim)
                }
                Spacer(minLength: 8)
                // Name only still shows a week: seven tiny dots before the check.
                if shown == .minimal { WeekStrip(data: row.progress, today: today, todayValue: todayCell).frame(width: 54) }
                GeometryReader { geo in
                    CheckButton(done: done, count: row.todayCount, target: t.target, size: 30) {
                        if !done && row.todayCount + 1 >= t.target {
                            let f = geo.frame(in: .global)
                            confetti.fire(at: CGPoint(x: f.midX, y: f.midY))
                        }
                        onToggle()
                    }
                }
                .frame(width: 30, height: 30)
            }
            switch shown {
            case .wall: FitHeatmap(data: row.progress, today: today, targetCell: 15, todayValue: todayCell, labels: true)
            case .compact: WeekStrip(data: row.progress, today: today, todayValue: todayCell, labels: true)
            case .chain:
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(row.streak)").font(Type.headlineMedium).contentTransition(.numericText(value: Double(row.streak)))
                    Text(row.streak == 1 ? "day streak" : "day streak").font(Type.labelMedium).foregroundStyle(palette.dim)
                    Spacer()
                }
                .animation(.default, value: row.streak)
                ChainStrip(data: row.progress, today: today, todayValue: todayCell).padding(.top, -6)
            case .month: MonthMini(data: row.progress, today: today, todayValue: todayCell)
            case .minimal, .ring: EmptyView()
            }
        }
        .padding(14)
    }
}

/// Habit icon on a soft rounded tile, HabitKit-style.
struct HabitIconTile: View {
    let icon: String
    var size: CGFloat = 36
    @Environment(\.palette) private var palette
    var body: some View {
        Image("Icons/\(icon)")
            .resizable()
            .frame(width: size * 0.58, height: size * 0.58)
            .foregroundStyle(palette.ink)
            .frame(width: size, height: size)
            .background(palette.tile, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// Streak as a flame and a number.
struct StreakLabel: View {
    let days: Int
    var body: some View {
        HStack(spacing: 3) {
            Image("Icons/ui-fire-fill").resizable().frame(width: 12.5, height: 12.5)
            Text("\(days)").contentTransition(.numericText(value: Double(days)))
        }
        .animation(.default, value: days)
    }
}

/// Solid round "+" with a soft press bounce.
struct AddButton: View {
    let label: String
    let action: () -> Void
    @Environment(\.palette) private var palette
    var body: some View {
        Button(action: action) {
            Image("Icons/ui-plus").resizable().frame(width: 22, height: 22)
                .foregroundStyle(palette.onInk)
                .frame(width: 44, height: 44)
                .background(palette.ink, in: Circle())
        }
        .buttonStyle(Bouncy(scale: 0.88))
        .accessibilityLabel(label)
    }
}

/// Round header button with a soft press bounce.
/// A small round button after the page title that opens the card style picker.
struct CardStyleButton: View {
    let sample: HabitRow?
    var second: HabitRow? = nil
    @State private var picking = false
    @AppStorage("cards") private var cards = CardStyle.wall
    @Environment(\.palette) private var palette
    var body: some View {
        Button { picking = true } label: {
            Image("Icons/ui-cards-wall").resizable().frame(width: 16, height: 16)
                .foregroundStyle(palette.dim)
                .frame(width: 30, height: 30)
                .background(palette.tile, in: Circle())
        }
        .buttonStyle(Bouncy(scale: 0.9))
        .accessibilityLabel("Card style, \(cards.label)")
        .sheet(isPresented: $picking) { CardStylePicker(sample: sample, second: second) }
    }
}

/// Every card style drawn with the user's own first habit, so the choice is made by looking, not
/// by reading. Pro styles carry a lock and open the paywall.
struct CardStylePicker: View {
    let sample: HabitRow?
    /// A second habit for the two-up preview.
    var second: HabitRow? = nil
    @AppStorage("cards") private var cards = CardStyle.wall
    @State private var store = Store.shared
    @State private var paywall = false
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ForEach(CardStyle.allCases, id: \.self) { s in
                        let locked = s.pro && !store.active
                        let on = cards == s
                        Button {
                            if locked { paywall = true; return }
                            cards = s
                            // Let the check land, then go: the list behind is already redrawn.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { dismiss() }
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                let row = sample ?? Self.demo(today: model.today)
                                if s.tiled {
                                    HStack(spacing: 12) {
                                        HabitCard(row: row, today: model.today, style: s) {}
                                        HabitCard(row: second ?? row, today: model.today, style: s) {}
                                    }
                                    .allowsHitTesting(false)
                                } else {
                                    HabitCard(row: row, today: model.today, style: s) {}.allowsHitTesting(false)
                                }
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(s.label).font(Type.titleSmall)
                                        Text(s.note).font(Type.bodySmall).foregroundStyle(palette.dim)
                                    }
                                    Spacer()
                                    if locked {
                                        Label("Pro", image: "Icons/ui-lock-simple").font(Type.labelMedium).foregroundStyle(palette.dim)
                                    } else {
                                        ZStack {
                                            Circle().fill(on ? palette.ink : .clear)
                                            Circle().stroke(on ? .clear : palette.outline, lineWidth: 1.5)
                                            if on { Image("Icons/ui-check").resizable().frame(width: 12, height: 12).foregroundStyle(palette.onInk) }
                                        }
                                        .frame(width: 22, height: 22)
                                    }
                                }
                                .padding(.horizontal, 4)
                            }
                            .padding(10)
                            .background(palette.background, in: RoundedRectangle(cornerRadius: Radius.medium + 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.medium + 6, style: .continuous)
                                .stroke(on ? palette.ink : palette.hairline, lineWidth: on ? 2 : 1))
                            .animation(.easeOut(duration: 0.2), value: on)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(s.label + (locked ? ", Pro" : on ? ", selected" : ""))
                    }
                }
                .padding(16)
            }
            .background(palette.surfaceLow)
            .navigationTitle("Card style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image("Icons/ui-x").resizable().frame(width: 18, height: 18) }.accessibilityLabel("Close")
                }
            }
        }
        .textCap()
        .presentationCornerRadius(Radius.sheet)
        .sheet(isPresented: $paywall) { Paywall() }
        .sensoryFeedback(.selection, trigger: cards)
    }

    /// With no habits yet, a sample one so the previews still mean something.
    static func demo(today: Day) -> HabitRow {
        var t = Tracker(name: "Read 20 pages", icon: "book-open")
        t.cue = "Make time for a good book"
        var progress: [Day: Double] = [:]
        for i in 0..<120 where (i * 37) % 11 < 8 { progress[today - i] = 1 }
        progress[today] = 0
        return HabitRow(tracker: t, progress: progress, todayCount: 0, streak: 12, mustNotMiss: false)
    }
}

struct RoundIconButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @Environment(\.palette) private var palette
    var body: some View {
        Button(action: action) {
            Image("Icons/\(icon)").resizable().frame(width: 22, height: 22)
                .foregroundStyle(palette.ink)
                .frame(width: 44, height: 44)
                .background(palette.tile, in: Circle())
        }
        .buttonStyle(Bouncy(scale: 0.9))
        .accessibilityLabel(label)
    }
}

/// Press shrinks, release springs back (Android: spring 0.4 / 600).
struct Bouncy: ButtonStyle {
    var scale: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.4), value: configuration.isPressed)
    }
}

/// The floating Habits | Inbox switch on glass.
struct Pill: View {
    @Binding var inbox: Bool
    @Environment(\.palette) private var palette
    var body: some View {
        HStack(spacing: 0) {
            item("ui-dots-nine", "Habits", selected: !inbox) { inbox = false }
            item("ui-tray", "Inbox", selected: inbox) { inbox = true }
        }
        .background(alignment: .leading) {
            Capsule().fill(palette.ink.opacity(0.1)).frame(width: 56, height: 44)
                .offset(x: inbox ? 56 : 0)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: inbox)
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(palette.hairline, lineWidth: 1))
    }

    private func item(_ icon: String, _ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image("Icons/\(icon)").resizable().frame(width: 24, height: 24)
                .foregroundStyle(selected ? palette.ink : palette.dim)
                .frame(width: 56, height: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: selected)
    }
}

struct EmptyHabits: View {
    let onAdd: () -> Void
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Every day is a dot").font(Type.titleMedium)
            Text("Add a habit and check it off each day. Start with your own or pick one below.")
                .font(Type.bodyMedium).foregroundStyle(palette.dim)
            Button("New habit", action: onAdd).font(Type.labelLarge).padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 24)
    }
}
