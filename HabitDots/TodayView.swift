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
    @Namespace private var zoom

    var body: some View {
        NavigationStack(path: $path) {
            home
                .toolbar(.hidden, for: .navigationBar)
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
            #if DEBUG
            // `-restore <path>` runs a restore on launch, to check it without tapping through Settings.
            if let i = args.firstIndex(of: "-restore"), i + 1 < args.count { try? model.restore(from: URL(fileURLWithPath: args[i + 1])) }
            #endif
        }
    }

    private var home: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                if inbox {
                    InboxView { taskSheet = $0 }.transition(.slide(-1))
                } else {
                    habits.transition(.slide(1))
                }
            }
            .animation(.easeOut(duration: 0.34), value: inbox)
        }
        .background(palette.background)
        .overlay(alignment: .bottom) { Pill(inbox: $inbox).padding(.bottom, 8) }
        .sheet(isPresented: $adding) { EditSheet(existing: nil) }
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
                RoundIconButton(icon: "ui-chart-bar", label: "Statistics") {}
                AddButton(label: inbox ? "New task" : "New habit") {
                    if inbox { var t = Task(title: ""); t.dueDate = model.today; taskSheet = t } else { adding = true }
                }
            }
            .padding(.vertical, 8)
            Text(inbox ? "Inbox" : "Habits")
                .font(Type.titleLarge)
                .frame(height: 48)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.22), value: inbox)
        }
        .padding(.horizontal, 16)
    }

    private var habits: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if let rows = model.rows, rows.isEmpty { EmptyHabits { adding = true } }
                ForEach(model.rows ?? []) { row in
                    HabitCard(row: row, today: model.today) { model.toggle(row.tracker) }
                        .contentShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                        .onTapGesture { path.append(row.id) }
                        .matchedTransitionSource(id: row.id, in: zoom) { $0.clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)) }
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 96)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.rows?.map(\.id))
        }
        .scrollIndicators(.hidden)
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
    let onToggle: () -> Void
    @Environment(\.palette) private var palette
    @Environment(Confetti.self) private var confetti
    @State private var todayCell: Double = 0
    @AppStorage("cards") private var cards = CardStyle.wall
    @AppStorage("pretendPro") private var pro = false

    var body: some View {
        let t = row.tracker
        let done = row.progress(on: today) >= 1
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                HabitIconTile(icon: t.icon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.name).font(Type.titleSmall).lineLimit(1)
                    HStack(spacing: 0) {
                        if row.mustNotMiss {
                            Text("Don't miss today!")
                        } else {
                            StreakLabel(days: row.streak)
                        }
                        if t.target > 1 { Text("  ·  \(min(row.todayCount, t.target))/\(t.target)") }
                        if let cue = t.cue, !cue.isEmpty { Text("  ·  \(cue)").lineLimit(1) }
                    }
                    .font(Type.bodySmall)
                    .foregroundStyle(palette.dim)
                }
                Spacer(minLength: 0)
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
            switch pro ? cards : .wall {
            case .wall: FitHeatmap(data: row.progress, today: today, targetCell: 15, todayValue: todayCell)
            case .compact: WeekStrip(data: row.progress, today: today, todayValue: todayCell)
            case .minimal: EmptyView()
            }
        }
        .padding(14)
        .background(palette.surfaceLow, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).stroke(palette.softBorder, lineWidth: 1))
        .onAppear { todayCell = row.progress(on: today) }
        .onChange(of: row.progress(on: today)) { _, v in withAnimation(.easeInOut(duration: 0.45)) { todayCell = v } }
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
