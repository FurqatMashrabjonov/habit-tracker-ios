import SwiftUI
import GRDB
import HabitData
import HabitDesign
import HabitDomain

/// A habit as a picture: card preview, light/dark choice, and the system share sheet. What you see
/// is what gets shared: the same card view is rendered to the image.
struct ShareHabitSheet: View {
    let tracker: Tracker
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var done: Set<Day> = []
    @State private var dark = false
    @State private var file: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                card.clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).stroke(palette.softBorder, lineWidth: 1))
                HStack {
                    Text("Appearance").font(Type.bodyLarge)
                    Spacer()
                    Picker("Appearance", selection: $dark) {
                        Text("Light").tag(false)
                        Text("Dark").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
                Spacer()
                Button {
                    file = render()
                } label: {
                    Label { Text("Share habit").font(Type.titleSmall) } icon: { Image("Icons/ui-share-network").resizable().frame(width: 20, height: 20) }
                        .foregroundStyle(palette.onInk)
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background(palette.ink, in: Capsule())
                }
                .buttonStyle(Bouncy(scale: 0.97))
            }
            .padding(16)
            .background(palette.surfaceLow)
            .navigationTitle("Share habit")
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
        .sheet(item: $file) { url in ShareSheet(items: [url]).presentationDetents([.medium, .large]) }
        .onAppear { dark = scheme == .dark }
        #if DEBUG
        .task {
            // `-render`: render the card once the history is in, to check the image without tapping.
            guard CommandLine.arguments.contains("-render") else { return }
            try? await _Concurrency.Task.sleep(for: .seconds(1))
            if let url = render() { try? FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: NSTemporaryDirectory()).deletingLastPathComponent().appendingPathComponent("Documents/share-check.png")) }
        }
        #endif
        .task {
            guard let id = tracker.id else { return }
            let target = tracker.target
            done = Set((try? await model.store.db.read { db in
                try Day.fetchAll(db, sql: "SELECT date FROM entry WHERE trackerId = ? AND value >= ?", arguments: [id, target])
            }) ?? [])
        }
    }

    private var card: some View {
        ShareCard(tracker: tracker, done: done, today: model.today, streak: model.rows?.first { $0.id == tracker.id }?.streak ?? 0).habitTheme(dark: dark)
    }

    /// The card at 3x, as a PNG in the temporary folder, named after the habit.
    @MainActor private func render() -> URL? {
        let r = ImageRenderer(content: card.frame(width: 360))
        r.scale = 3
        guard let data = r.uiImage?.pngData() else { return nil }
        let name = tracker.name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "_")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent((name.isEmpty ? "habit" : name) + ".png")
        try? data.write(to: url)
        return url
    }
}

private struct ShareCard: View {
    let tracker: Tracker
    let done: Set<Day>
    let today: Day
    /// The home screen's streak, which already steps over off and rest days.
    let streak: Int
    @Environment(\.palette) private var palette
    var body: some View {
        let rule = tracker.rule
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                HabitIconTile(icon: tracker.icon, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tracker.name).font(Type.titleMedium)
                    HStack(spacing: 3) {
                        Image("Icons/ui-fire-fill").resizable().frame(width: 13, height: 13)
                        Text("\(streak)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(palette.dim)
                }
            }
            LabeledHeatmap(data: Dictionary(uniqueKeysWithValues: done.map { ($0, 1.0) }), today: today).padding(.top, 14)
            // The count, and where the card comes from: a shared wall is how most people find the app.
            HStack {
                Text("\(done.count) completions").font(.system(size: 11, weight: .medium, design: .monospaced))
                Spacer()
                Text("HabitDots").font(Type.labelSmall)
            }
            .foregroundStyle(palette.dim).padding(.top, 10)
        }
        .padding(18)
        .background(palette.background)
    }
}
