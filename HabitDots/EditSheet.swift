import SwiftUI
import HabitData
import HabitDesign
import HabitDomain

/// A ready-made habit: one tap fills the editor, everything stays editable. Same list as Android.
struct Template: Hashable {
    let name: String
    let icon: String
    var cue: String? = nil
    var schedule: Schedule = .daily

    static let all: [Template] = [
        .init(name: "Drink water", icon: "drop", cue: "8 glasses through the day"),
        .init(name: "Read 20 pages", icon: "book-open", cue: "Make time for a good book"),
        .init(name: "Morning run", icon: "person-simple-run"),
        .init(name: "Meditate", icon: "flower-lotus", cue: "10 quiet minutes"),
        .init(name: "Workout", icon: "barbell", schedule: .perWeek(3)),
        .init(name: "Walk", icon: "person-simple-walk", cue: "At least 30 minutes"),
        .init(name: "Sleep by 23:00", icon: "moon-stars"),
        .init(name: "No sugar", icon: "prohibit"),
        .init(name: "Journal", icon: "notebook", cue: "A few lines before bed"),
        .init(name: "Learn a language", icon: "translate"),
        .init(name: "Pray", icon: "hands-praying"),
        .init(name: "Stretch", icon: "person-simple-tai-chi"),
        .init(name: "Floss", icon: "tooth"),
        .init(name: "No phone in bed", icon: "device-mobile-slash"),
        .init(name: "Practice music", icon: "guitar", schedule: .weekdays(Repeat.workdays)),
        .init(name: "Save money", icon: "piggy-bank"),
    ]

    func apply(to t: inout Tracker) {
        t.name = name
        t.icon = icon
        t.cue = cue
        t.schedule = schedule.encode()
    }
}

/// New / edit habit as a full-height sheet: a big icon on top (tap to change it on a second page),
/// then name, description, frequency, times a day, reminder, and a pinned Save button.
struct EditSheet: View {
    let existing: Tracker?
    var onDeleted: () -> Void = {}
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var t: Tracker
    @State private var confirmDelete = false
    @State private var paywall = false
    @FocusState private var focus: Field?
    private enum Field { case name, cue }

    init(existing: Tracker?, onDeleted: @escaping () -> Void = {}) {
        self.existing = existing
        self.onDeleted = onDeleted
        _t = State(initialValue: existing ?? Tracker(name: "", icon: ""))
    }

    private var isNew: Bool { existing == nil }
    private var canSave: Bool { !t.name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    NavigationLink { IconPicker(selected: $t.icon) } label: { IconHeader(icon: t.icon) }
                        .buttonStyle(.plain)
                    // The free limit, shown before it's hit rather than as a surprise at the sixth habit.
                    if isNew && !Store.shared.active {
                        Text("\(app.rows?.count ?? 0) of \(Store.freeHabits) free habits")
                            .font(Type.bodySmall).foregroundStyle(palette.dim).frame(maxWidth: .infinity)
                    }
                    SoftField(title: "Name", text: $t.name, max: nameMax).focused($focus, equals: .name)
                    if isNew && t.name.isEmpty {
                        Label("Or start from a template")
                        FlowLayout(spacing: 8) {
                            ForEach(Template.all, id: \.self) { tpl in
                                Button { withAnimation(.snappy) { tpl.apply(to: &t) } } label: {
                                    HStack(spacing: 6) {
                                        Image("Icons/\(tpl.icon)").resizable().frame(width: 18, height: 18)
                                        Text(tpl.name).font(Type.bodyMedium)
                                    }
                                    .padding(.leading, 12).padding(.trailing, 14).padding(.vertical, 8)
                                    .background(palette.background, in: Capsule())
                                    .overlay(Capsule().stroke(palette.softBorder, lineWidth: 1))
                                }
                                .buttonStyle(Bouncy(scale: 0.95))
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    SoftField(title: "Description", text: Binding($t.cue, default: ""), max: textMax, multiline: true).focused($focus, equals: .cue)
                    Label("Frequency")
                    FrequencyPicker(rule: Binding(get: { t.rule }, set: { t.schedule = $0.encode() }))
                    Label("Times a day")
                    HStack(spacing: 6) {
                        ForEach(1...6, id: \.self) { n in Choice(label: "\(n)", selected: t.target == n, fill: true) { t.dailyTarget = n } }
                    }
                    Label("Reminder")
                    ReminderChip(time: $t.reminder)
                    if !isNew {
                        Toggle("Archived", isOn: $t.archived).font(Type.bodyLarge).tint(palette.ink).padding(.top, 4)
                        Button("Delete habit", role: .destructive) { confirmDelete = true }
                            .font(Type.labelLarge).foregroundStyle(palette.error).padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 96)
                .animation(.snappy, value: t.name.isEmpty)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(palette.surfaceLow)
            .safeAreaInset(edge: .bottom) {
                if focus == nil {
                    Button(action: save) {
                        Text("Save").font(Type.titleSmall).frame(maxWidth: .infinity).frame(height: 54)
                            .foregroundStyle(canSave ? palette.onInk : palette.dim)
                            .background(canSave ? palette.ink : palette.tileHigh, in: Capsule())
                    }
                    .disabled(!canSave)
                    .buttonStyle(Bouncy(scale: 0.97))
                    .padding(.horizontal, 16).padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: focus == nil)
            .navigationTitle(isNew ? "New habit" : "Edit habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image("Icons/ui-x").resizable().frame(width: 18, height: 18) }.accessibilityLabel("Close")
                }
                ToolbarItem(placement: .keyboard) { HStack { Spacer(); Button("Done") { focus = nil } } }
            }
            .confirmationDialog("Delete habit", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    app.delete(t)
                    dismiss()
                    onDeleted()
                }
            } message: {
                Text("“\(t.name)” and its whole history are removed from every phone. You can restore it from Settings › Recently deleted for 30 days.")
            }
        }
        .presentationDetents([.large])
        .textCap()
        .presentationCornerRadius(Radius.sheet)
        .presentationBackground(palette.surfaceLow)
        .sheet(isPresented: $paywall) { Paywall() }
    }

    private func save() {
        // Bringing a habit back from the archive past the free limit needs Pro (a new one is checked
        // before the editor opens).
        if existing?.archived == true && !t.archived && !Store.shared.canAddHabit(activeHabits: app.rows?.count ?? 0) {
            paywall = true
            return
        }
        var row = t
        row.name = row.name.trimmingCharacters(in: .whitespaces)
        row.cue = row.cue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        row.type = .boolean
        row.dailyTarget = row.target
        if isNew { row.createdAt = Clock.nowMillis() }
        _Concurrency.Task { try? await app.store.save(row) }
        dismiss()
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }

extension Binding where Value == String {
    /// A text field over an optional string: empty text stores nil.
    init(_ source: Binding<String?>, default fallback: String) {
        self.init(get: { source.wrappedValue ?? fallback }, set: { source.wrappedValue = $0.isEmpty ? nil : $0 })
    }
}

private struct Label: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(Type.labelLarge) }
}

/// Input without a hard outline: a soft gray field with rounded corners; a faint ring when focused.
struct SoftField: View {
    let title: String
    @Binding var text: String
    var max: Int
    var multiline = false
    @Environment(\.palette) private var palette
    @Environment(\.isFocused) private var isFocused
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !text.isEmpty { Text(title).font(Type.labelMedium).foregroundStyle(palette.dim).transition(.opacity) }
            TextField(title, text: $text, axis: multiline ? .vertical : .horizontal)
                .font(Type.bodyLarge)
                .lineLimit(multiline ? 1...5 : 1...1)
        }
        .animation(.easeOut(duration: 0.15), value: text.isEmpty)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.tile, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .onChange(of: text) { _, v in if v.count > max { text = String(v.prefix(max)) } }
    }
}

/// The chosen icon, big, over a faint field of other icons; tapping it opens the picker.
private struct IconHeader: View {
    let icon: String
    @Environment(\.palette) private var palette
    @State private var field = Array(habitIconKeys.shuffled().prefix(24))
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(field[(r * 8)..<(r * 8 + 8)], id: \.self) { k in
                            Image("Icons/\(k)").resizable().frame(width: 22, height: 22).foregroundStyle(palette.ink.opacity(0.08)).frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            VStack(spacing: 8) {
                Group {
                    if icon.isEmpty { Image("Icons/ui-pencil-simple").resizable().frame(width: 32, height: 32).foregroundStyle(palette.dim) }
                    else { Image("Icons/\(icon)").resizable().frame(width: 48, height: 48) }
                }
                .frame(width: 88, height: 88)
                .background(palette.tile, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                Text("Change icon").font(Type.labelLarge)
            }
        }
        .frame(height: 150)
        .contentShape(Rectangle())
    }
}

/// All habit icons in a grid; tap to choose, tap the chosen one again for no icon.
private struct IconPicker: View {
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], spacing: 6) {
                ForEach(habitIconKeys, id: \.self) { key in
                    let on = key == selected
                    Button { selected = on ? "" : key; dismiss() } label: {
                        Image("Icons/\(key)").resizable().frame(width: 24, height: 24)
                            .foregroundStyle(on ? palette.onInk : palette.ink)
                            .frame(width: 44, height: 44)
                            .background(on ? palette.ink : palette.tile, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                    }
                    .buttonStyle(Bouncy(scale: 0.9))
                    .accessibilityLabel(key)
                }
            }
            .padding(16)
        }
        .background(palette.surfaceLow)
        .navigationTitle("Icon")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FrequencyPicker: View {
    @Binding var rule: Schedule
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Choice(label: "Every day", selected: rule == .daily) { rule = .daily }
                Choice(label: "Specific days", selected: { if case .weekdays = rule { true } else { false } }()) {
                    if case .weekdays = rule {} else { rule = .weekdays(Repeat.workdays) }
                }
                Choice(label: "N times a week", selected: { if case .perWeek = rule { true } else { false } }()) {
                    if case .perWeek = rule {} else { rule = .perWeek(3) }
                }
            }
            switch rule {
            case .weekdays(let days):
                HStack(spacing: 6) {
                    ForEach(1...7, id: \.self) { d in
                        let on = days.contains(d)
                        Choice(label: Words.weekdaysShort[d - 1], selected: on, fill: true) {
                            let next = on ? days.subtracting([d]) : days.union([d])
                            if !next.isEmpty { rule = .weekdays(next) }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            case .perWeek(let n):
                HStack(spacing: 6) {
                    ForEach(1...6, id: \.self) { k in Choice(label: "\(k)", selected: n == k, fill: true) { rule = .perWeek(k) } }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            case .daily:
                EmptyView()
            }
        }
        .animation(.snappy, value: rule)
    }
}

struct Choice: View {
    let label: String
    let selected: Bool
    var fill = false
    let action: () -> Void
    @Environment(\.palette) private var palette
    var body: some View {
        Button(action: action) {
            Text(label).font(Type.labelLarge).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(selected ? palette.onInk : palette.ink)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: fill ? .infinity : nil)
                .background(selected ? palette.ink : palette.tile, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                .animation(.easeOut(duration: 0.22), value: selected)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// "Reminder" chip that opens a time picker; set times can be cleared.
struct ReminderChip: View {
    @Binding var time: ClockTime?
    @State private var picking = false
    @Environment(\.palette) private var palette
    var body: some View {
        HStack(spacing: 8) {
            Button { picking = true } label: {
                HStack(spacing: 8) {
                    Image("Icons/ui-bell").resizable().frame(width: 18, height: 18)
                    Text(time?.description ?? "Reminder").font(Type.labelLarge)
                }
                .foregroundStyle(time != nil ? palette.onInk : palette.ink)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(time != nil ? palette.ink : palette.tile, in: Capsule())
            }
            .buttonStyle(Bouncy(scale: 0.95))
            if time != nil {
                Button { time = nil } label: { Image("Icons/ui-x").resizable().frame(width: 14, height: 14).padding(10).background(palette.tile, in: Circle()) }
                    .buttonStyle(.plain).accessibilityLabel("No reminder")
            }
        }
        .sheet(isPresented: $picking) {
            TimeSheet(time: time ?? ClockTime((Calendar.current.component(.hour, from: Date()) + 1) % 24, 0)) { time = $0; Reminders.askPermission() }
        }
    }
}

struct TimeSheet: View {
    @State var time: ClockTime
    let onPick: (ClockTime) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            DatePicker("", selection: Binding(
                get: { Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date() },
                set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); time = ClockTime(c.hour ?? 0, c.minute ?? 0) }
            ), displayedComponents: .hourAndMinute)
            .datePickerStyle(.wheel)
            .labelsHidden()
            .navigationTitle("Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Set") { onPick(time); dismiss() } }
            }
        }
        .presentationDetents([.height(320)])
        .textCap()
    }
}

/// A task's own weekdays ("Mon, Wed, Fri"); at least one stays on.
struct WeekdaysSheet: View {
    @State var days: Set<Int>
    let onPick: (Set<Int>) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { d in
                    let on = days.contains(d)
                    Choice(label: Words.weekdaysShort[d - 1], selected: on, fill: true) {
                        let next = on ? days.subtracting([d]) : days.union([d])
                        if !next.isEmpty { days = next }
                    }
                }
            }
            .padding(16)
            .navigationTitle("Repeat on")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Set") { onPick(days); dismiss() } }
            }
        }
        .presentationDetents([.height(160)])
        .textCap()
    }
}

/// Wraps children onto new lines, like Compose's FlowRow.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing
            row = max(row, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            row = max(row, s.height)
        }
    }
}
