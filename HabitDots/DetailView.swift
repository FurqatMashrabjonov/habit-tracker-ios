import SwiftUI
import HabitData
import HabitDesign
import HabitDomain

/// HabitKit-style, as on Android: name and today's check, the dot history, the three numbers, a
/// calendar (tap a day to pick it), the picked day's panel (check it, write a note) and the notes.
struct DetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var model: DetailModel
    @State private var day: Day
    @State private var noteDay: Day?
    @State private var confirmDelete = false
    @State private var editing = false

    init(id: Int64, store: HabitStore, today: Day) {
        _model = State(initialValue: DetailModel(id: id, store: store))
        _day = State(initialValue: today)
    }

    var body: some View {
        ScrollView {
            if let s = model.state {
                content(s)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
            }
        }
        .scrollIndicators(.hidden)
        .background(palette.background)
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.start(today: app.today) }
        .sheet(item: $noteDay) { d in
            NoteSheet(title: "\(model.state?.tracker.name ?? "") · \(Words.date(d))", initial: model.state?.note(on: d) ?? "") { text in
                model.saveNote(text, on: d)
            }
        }
        .sheet(isPresented: $editing) {
            if let t = model.state?.tracker { EditSheet(existing: t, onDeleted: { dismiss() }) }
        }
        .confirmationDialog("Delete habit", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { dismiss(); model.delete() }
        } message: {
            Text("“\(model.state?.tracker.name ?? "")” and its whole history are removed from every phone. You can restore it from Settings › Recently deleted for 30 days.")
        }
    }

    @ViewBuilder
    private func content(_ s: DetailState) -> some View {
        let t = s.tracker
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                RoundIcon(icon: "ui-arrow-left", label: "Back") { dismiss() }
                Spacer()
                RoundIcon(icon: "ui-pencil-simple", label: "Edit") { editing = true }
                Menu {
                    Button { } label: { Label("Share", image: "Icons/ui-share-network") }
                    Button { model.archive(); dismiss() } label: { Label("Archive", image: "Icons/ui-archive") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", image: "Icons/ui-trash") }
                } label: { RoundIconLabel(icon: "ui-dots-three") }
                .accessibilityLabel("Menu")
            }
            HStack(spacing: 14) {
                HabitIconTile(icon: t.icon, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.name).font(Type.headlineSmall)
                    Text(Words.schedule(t.rule) ?? "Every day").font(Type.labelMedium).foregroundStyle(palette.dim)
                }
                Spacer(minLength: 0)
                CheckButton(done: s.isDone(s.today), count: s.value(on: s.today), target: t.target, size: 40) { model.toggle(on: s.today) }
            }
            .padding(.top, 4)
            if let cue = t.cue, !cue.isEmpty {
                Text(cue).font(Type.bodyMedium).foregroundStyle(palette.dim).frame(maxWidth: .infinity, alignment: .leading)
            }
            SectionCard { LabeledHeatmap(data: s.progress, today: s.today) }
            HStack(spacing: 8) {
                Stat(label: "Streak", value: s.currentStreak, flame: true)
                Stat(label: "Best streak", value: s.bestStreak)
                Stat(label: "Total", value: s.done.count)
            }
            .fixedSize(horizontal: false, vertical: true)
            SectionCard {
                MonthCalendar(s: s, selected: $day)
                Divider().overlay(palette.hairline).padding(.vertical, 12)
                DayPanel(s: s, day: day, onToggle: { model.toggle(on: day) }, onNote: { noteDay = day })
            }
            if !s.notes.isEmpty { Notes(s: s) { d in day = d; noteDay = d } }
        }
    }
}

extension Day: @retroactive Identifiable { public var id: Int { epochDay } }

struct SectionCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surfaceLow, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).stroke(palette.softBorder, lineWidth: 1))
    }
}

/// A big number that counts up from 0 on first show, then glides between values (700 ms ease-out).
struct Stat: View {
    let label: String
    let value: Int
    var flame = false
    @Environment(\.palette) private var palette
    @State private var shown = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                if flame { Image("Icons/ui-fire-fill").resizable().frame(width: 27, height: 27) }
                Text("\(shown)").font(Type.inter(28, .semibold)).contentTransition(.numericText(value: Double(shown)))
            }
            Text(label).font(Type.labelMedium).foregroundStyle(palette.dim).lineLimit(1)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(palette.surfaceLow, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).stroke(palette.softBorder, lineWidth: 1))
        .onAppear { withAnimation(.easeOut(duration: 0.7)) { shown = value } }
        .onChange(of: value) { _, v in withAnimation(.easeOut(duration: 0.7)) { shown = v } }
    }
}

struct RoundIcon: View {
    let icon: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { RoundIconLabel(icon: icon) }.buttonStyle(Bouncy(scale: 0.9)).accessibilityLabel(label)
    }
}

struct RoundIconLabel: View {
    let icon: String
    var enabled = true
    @Environment(\.palette) private var palette
    var body: some View {
        Image("Icons/\(icon)").resizable().frame(width: 20, height: 20)
            .foregroundStyle(palette.ink)
            .frame(width: 40, height: 40)
            .background(palette.tile, in: Circle())
            .opacity(enabled ? 1 : 0.35)
    }
}

/// Month grid: done days solid, the picked day ringed, today faintly ringed, a dot under days with a note.
struct MonthCalendar: View {
    let s: DetailState
    @Binding var selected: Day
    @State private var month: Day = .today // any day of the shown month
    @Environment(\.palette) private var palette

    var body: some View {
        let first = month.withDay(1)
        let lead = first.weekday - 1
        let length = first.lengthOfMonth
        let created = Day.from(millis: s.tracker.createdAt)
        VStack(spacing: 0) {
            CalendarHeader(month: $month, today: s.today, first: min(created, s.today)) {
                month = s.today; selected = s.today
            }
            HStack(spacing: 0) {
                ForEach(Words.weekdaysShort, id: \.self) { Text($0).font(Type.labelSmall).foregroundStyle(palette.dim).frame(maxWidth: .infinity) }
            }
            .padding(.vertical, 6)
            let weeks = (lead + length + 6) / 7
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(0..<weeks, id: \.self) { week in
                    GridRow {
                        ForEach(0..<7, id: \.self) { col in
                            let n = week * 7 + col - lead + 1
                            if n >= 1 && n <= length {
                                cell(first.withDay(n))
                            } else {
                                Color.clear.aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { month = selected }
        .onChange(of: selected) { _, d in if d.withDay(1) != month.withDay(1) { month = d } }
    }

    private func cell(_ date: Day) -> some View {
        let future = date > s.today
        let done = s.isDone(date)
        let shape = RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
        return Button { selected = date } label: {
            ZStack(alignment: .bottom) {
                shape.fill(done ? palette.ink : .clear)
                if date == selected {
                    shape.strokeBorder(done ? palette.onInk.opacity(0.8) : palette.ink, lineWidth: 2)
                } else if date == s.today && !done {
                    shape.strokeBorder(palette.ink.opacity(0.4), lineWidth: 1)
                }
                Text("\(date.day)").font(Type.labelMedium)
                    .foregroundStyle(done ? palette.onInk : future ? palette.dim.opacity(0.45) : palette.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if s.note(on: date) != nil {
                    Circle().fill(done ? palette.onInk : palette.ink).frame(width: 4, height: 4).padding(.bottom, 4)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: done)
        }
        .buttonStyle(.plain)
        .disabled(future)
        .aspectRatio(1, contentMode: .fit)
        .padding(3)
    }
}

/// Month menu (every month since the habit started), a Today button and arrows.
struct CalendarHeader: View {
    @Binding var month: Day
    let today: Day
    let first: Day
    let onToday: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        let mono = Font.system(size: 14, weight: .medium, design: .monospaced)
        let canNext = month.withDay(1) < today.withDay(1)
        HStack(spacing: 6) {
            Menu {
                ForEach(months, id: \.self) { m in
                    Button { month = m } label: {
                        if m.withDay(1) == month.withDay(1) { Label("\(Words.months[m.month - 1]) \(String(m.year))", image: "Icons/ui-check") }
                        else { Text("\(Words.months[m.month - 1]) \(String(m.year))") }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text("\(Words.months[month.month - 1].prefix(3)) \(String(month.year))").font(mono).contentTransition(.numericText())
                    Image("Icons/ui-caret-down").resizable().frame(width: 14, height: 14)
                }
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(palette.tile, in: Capsule())
            }
            Spacer()
            Button(action: onToday) {
                Text("Today").font(Type.labelLarge).foregroundStyle(palette.ink)
                    .padding(.horizontal, 14).padding(.vertical, 9).background(palette.tile, in: Capsule())
            }
            .buttonStyle(Bouncy(scale: 0.92))
            .padding(.trailing, 2)
            RoundIcon(icon: "ui-caret-left", label: "Previous month") { withAnimation { month = month.withDay(1).addingMonths(-1) } }
            Button { if canNext { withAnimation { month = month.withDay(1).addingMonths(1) } } } label: {
                RoundIconLabel(icon: "ui-caret-right", enabled: canNext)
            }
            .buttonStyle(Bouncy(scale: 0.9))
            .accessibilityLabel("Next month")
        }
        .padding(.bottom, 6)
    }

    /// Newest first, back to the habit's first month (at most three years).
    private var months: [Day] {
        var out: [Day] = []
        var m = today.withDay(1)
        let stop = first.withDay(1)
        while m >= stop && out.count < 36 { out.append(m); m = m.addingMonths(-1) }
        return out
    }
}

/// The picked day: its date, whether it was done (with a check to change it) and its note.
struct DayPanel: View {
    let s: DetailState
    let day: Day
    let onToggle: () -> Void
    let onNote: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        let value = s.value(on: day)
        let done = s.isDone(day)
        let status: String = {
            if done { return "Done" }
            if s.tracker.target > 1 && value > 0 { return "\(value)/\(s.tracker.target)" }
            if s.tracker.rule.skip(day, done: s.done, today: s.today) { return "Day off" }
            return day == s.today ? "Not yet" : "Not done"
        }()
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Words.longDate(day, today: s.today)).font(Type.titleSmall).contentTransition(.opacity)
                    Text(status).font(Type.bodySmall).foregroundStyle(palette.dim).contentTransition(.opacity)
                }
                .animation(.easeOut(duration: 0.2), value: day)
                Spacer()
                CheckButton(done: done, count: value, target: s.tracker.target, size: 36, onTap: onToggle)
                    .id(day) // a new day starts from its own state instead of animating from the last one
            }
            Button(action: onNote) {
                HStack(spacing: 10) {
                    if let note = s.note(on: day) {
                        Text(note).font(Type.bodyMedium).foregroundStyle(palette.ink).multilineTextAlignment(.leading)
                    } else {
                        Image("Icons/ui-note-pencil-line").resizable().frame(width: 18, height: 18)
                        Text("Add note").font(Type.bodyMedium)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(palette.dim)
                .padding(12)
                .background(palette.tile, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

/// Every note, newest first and grouped by month, like a journal; tap one to open its day.
struct Notes: View {
    let s: DetailState
    let onOpen: (Day) -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        let groups = Dictionary(grouping: s.notes) { $0.date.withDay(1) }.sorted { $0.key > $1.key }
        SectionCard {
            Text("Notes · \(s.notes.count)").font(Type.titleSmall)
            ForEach(groups, id: \.key) { month, notes in
                Text("\(Words.months[month.month - 1]) \(String(month.year))").font(Type.labelMedium).foregroundStyle(palette.dim)
                    .padding(.top, 14).padding(.bottom, 4)
                ForEach(notes, id: \.date) { note in
                    Button { onOpen(note.date) } label: {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(spacing: 0) {
                                Text("\(note.date.day)").font(Type.titleMedium)
                                Text(Words.weekdaysShort[note.date.weekday - 1]).font(Type.labelSmall).foregroundStyle(palette.dim)
                                Circle().fill(s.isDone(note.date) ? palette.ink : .clear)
                                    .overlay(Circle().stroke(s.isDone(note.date) ? .clear : palette.dim, lineWidth: 1))
                                    .frame(width: 6, height: 6).padding(.top, 4)
                            }
                            .frame(width: 44)
                            Text(note.text).font(Type.bodyMedium).lineLimit(4).multilineTextAlignment(.leading).padding(.top, 2)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// A day's note. Saving blank text removes it.
struct NoteSheet: View {
    let title: String
    let initial: String
    let onSave: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    var body: some View {
        NavigationStack {
            TextField("What went well? What got in the way?", text: $text, axis: .vertical)
                .font(Type.bodyLarge)
                .lineLimit(3...12)
                .focused($focused)
                .padding(14)
                .background(palette.tile, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                .padding(16)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(palette.surfaceLow)
                .onChange(of: text) { _, v in if v.count > noteMax { text = String(v.prefix(noteMax)) } }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(text); dismiss() } }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Radius.sheet)
        .onAppear { text = initial; focused = true }
    }
}
