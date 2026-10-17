import SwiftUI
import HabitData
import HabitDesign
import HabitDomain

/// Tasks next to the habits, as on Android: Overdue, Today, Upcoming and No date, each a soft card of rows.
struct InboxView: View {
    let onOpen: (Task) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        let today = model.today
        let tasks = model.tasks
        let groups: [(String, [Task])] = [
            ("Overdue", tasks.filter { $0.dueDate.map { $0 < today } == true }),
            ("Today", tasks.filter { $0.dueDate == today }),
            ("Upcoming", tasks.filter { $0.dueDate.map { $0 > today } == true }),
            ("No date", tasks.filter { $0.dueDate == nil }),
        ].filter { !$0.1.isEmpty }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if tasks.isEmpty {
                    Text("No tasks").font(Type.bodyMedium).foregroundStyle(palette.dim).frame(maxWidth: .infinity).padding(48)
                }
                ForEach(groups, id: \.0) { title, items in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title).font(Type.titleMedium)
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { i, task in
                                if i > 0 { Divider().overlay(palette.hairline).padding(.leading, 52) }
                                TaskRow(task: task, today: today, onComplete: { model.complete(task) }, onOpen: { onOpen(task) })
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(.vertical, 6)
                        .background(palette.background, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.small, style: .continuous).stroke(palette.softBorder, lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 96)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: tasks.map(\.id))
        }
        .scrollIndicators(.hidden)
    }
}

/// Tapping the check plays it first, then the task leaves the list (or moves on, when it repeats).
struct TaskRow: View {
    let task: Task
    let today: Day
    let onComplete: () -> Void
    let onOpen: () -> Void
    @Environment(\.palette) private var palette
    @State private var completing = false

    var body: some View {
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let overdue = task.overdue(today: today, now: ClockTime(now.hour ?? 0, now.minute ?? 0))
        let meta = [
            task.dueDate.flatMap { $0 == today ? nil : Words.due($0, today: today) },
            task.dueTime?.description,
            Repeat.decode(task.repeat).map { Words.repeat($0) },
        ].compactMap { $0 }.joined(separator: "  ·  ")
        HStack(spacing: 12) {
            CheckButton(done: completing, size: 28) {
                guard !completing else { return }
                completing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) { onComplete() }
            }
            .accessibilityLabel("Complete \(task.title)")
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    // A flag in ink, darker the more urgent, as on the widget.
                    if let a = Priority.alpha(task.priority) {
                        Image("Icons/flag").resizable().frame(width: 16, height: 16).opacity(a).accessibilityLabel("Priority \(task.priority)")
                    }
                    Text(task.title).font(Type.bodyLarge).lineLimit(2).strikethrough(completing)
                }
                if !meta.isEmpty {
                    // Overdue is bold ink, never red: the app stays black and white.
                    Text(meta).font(overdue ? Type.inter(12, .bold) : Type.labelMedium).foregroundStyle(overdue ? palette.ink : palette.dim)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .opacity(completing ? 0.45 : 1)
        .animation(.easeOut(duration: 0.4), value: completing)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onChange(of: task.dueDate) { _, _ in completing = false } // a repeating task came back with its next date
    }
}

/// Todoist-style quick add / edit: a small card above the keyboard with the title and chips for
/// date, time and repeat, and send at the end.
struct TaskSheet: View {
    let initial: Task
    let today: Day
    let onSave: (Task) -> Void
    let onDelete: (() -> Void)?
    @State private var title = ""
    @State private var date: Day?
    @State private var time: ClockTime?
    @State private var rule: Repeat?
    @State private var priority = Priority.none
    @State private var pickingDate = false
    @State private var pickingTime = false
    @State private var pickingDays = false
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("e.g. Pick up the book", text: $title)
                .font(Type.titleMedium)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(save)
                .onChange(of: title) { _, v in if v.count > textMax { title = String(v.prefix(textMax)) } }
            HStack(spacing: 8) {
                if let onDelete {
                    Button { onDelete(); dismiss() } label: {
                        Image("Icons/ui-trash").resizable().frame(width: 20, height: 20).foregroundStyle(palette.error)
                    }
                    .accessibilityLabel("Delete")
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        Menu {
                            Button("Today") { date = today }
                            Button("Tomorrow") { date = today + 1 }
                            Button("Pick a date…") { pickingDate = true }
                            Button("No date") { date = nil }
                        } label: { Chip(label: date.map { Words.due($0, today: today) } ?? "Date", icon: "ui-calendar-blank", active: date != nil) }
                        Button { pickingTime = true } label: { Chip(label: time?.description ?? "Reminder", icon: "ui-bell", active: time != nil) }
                        Menu {
                            let anchor = date ?? today
                            Button("Doesn't repeat") { rule = nil }
                            ForEach([Repeat.daily, .weekly(Repeat.workdays), .weekly([anchor.weekday]), .monthly(anchor.day)], id: \.self) { r in
                                Button(Words.repeat(r)) { rule = r }
                            }
                            Button("Pick days…") { pickingDays = true }
                            Menu("Every N days…") {
                                ForEach(2...14, id: \.self) { n in Button("Every \(n) days") { rule = .everyDays(n) } }
                            }
                        } label: { Chip(label: rule.map { Words.repeat($0) } ?? "Repeat", icon: "ui-arrows-clockwise", active: rule != nil) }
                        Menu {
                            ForEach(1...Priority.none, id: \.self) { p in
                                Button { priority = p } label: { Label("Priority \(p)", image: "Icons/flag") }
                            }
                        } label: {
                            Chip(label: priority == Priority.none ? "Priority" : "P\(priority)", icon: "flag", active: priority != Priority.none,
                                 tint: Priority.alpha(priority))
                        }
                    }
                }
                .scrollIndicators(.hidden)
                Button(action: save) {
                    Image("Icons/ui-paper-plane-right").resizable().frame(width: 20, height: 20)
                        .foregroundStyle(canSave ? palette.onInk : palette.dim)
                        .frame(width: 40, height: 40)
                        .background(canSave ? palette.ink : palette.tile, in: Circle())
                }
                .disabled(!canSave)
                .accessibilityLabel("Save")
            }
        }
        .padding(16)
        .presentationDetents([.height(132)])
        .textCap()
        .presentationCornerRadius(Radius.sheet)
        .presentationBackground(palette.surfaceLow)
        .onAppear {
            title = initial.title; date = initial.dueDate; time = initial.dueTime; rule = Repeat.decode(initial.repeat); priority = initial.priority
            focused = true
        }
        .sheet(isPresented: $pickingDate) {
            DateSheet(day: date ?? today, from: today) { date = $0 }
        }
        .sheet(isPresented: $pickingDays) {
            let current: Set<Int> = if case .weekly(let d) = rule { d } else { [(date ?? today).weekday] }
            WeekdaysSheet(days: current) { rule = .weekly($0) }
        }
        .sheet(isPresented: $pickingTime) {
            TimeSheet(time: time ?? ClockTime((Calendar.current.component(.hour, from: Date()) + 1) % 24, 0)) { time = $0; Reminders.askPermission() }
        }
    }

    private func save() {
        guard canSave else { return }
        var t = initial
        // Quick add like Todoist: "Pay rent p1" saves "Pay rent" at priority 1.
        let (clean, tagged) = Priority.parse(title.trimmingCharacters(in: .whitespaces))
        t.title = clean
        t.priority = tagged ?? priority
        // A time or a repeat needs a day to hang on: today when none was picked.
        t.dueDate = date ?? ((time != nil || rule != nil) ? today : nil)
        t.dueTime = time
        t.repeat = rule?.encode()
        onSave(t)
        dismiss()
    }
}

private struct Chip: View {
    let label: String
    let icon: String
    let active: Bool
    /// Ink depth for the icon (a priority flag); nil draws it like the label.
    var tint: Double? = nil
    @Environment(\.palette) private var palette
    var body: some View {
        HStack(spacing: 6) {
            Image("Icons/\(icon)").resizable().frame(width: 18, height: 18).opacity(active ? (tint ?? 1) : 1)
            Text(label).font(Type.labelLarge)
        }
        .foregroundStyle(active ? palette.ink : palette.dim)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(palette.tile, in: Capsule())
    }
}

private struct DateSheet: View {
    @State var day: Day
    let from: Day
    let onPick: (Day) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            DatePicker("", selection: Binding(
                get: { Calendar.current.date(from: DateComponents(year: day.year, month: day.month, day: day.day)) ?? Date() },
                set: { day = .from(date: $0) }
            ), displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding(.horizontal)
            .navigationTitle("Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Set") { onPick(day); dismiss() } }
            }
        }
        .presentationDetents([.medium])
        .textCap()
    }
}

extension Task: @retroactive Identifiable {}
