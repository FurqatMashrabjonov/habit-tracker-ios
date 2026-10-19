#if DEBUG
import SwiftUI
import WidgetKit
import HabitData
import HabitDesign
import HabitDomain

/// Debug only (`-widgets`): every widget at its real size, over a wallpaper, fed from this phone's data.
struct WidgetGallery: View {
    let look: WidgetLook
    @State private var habits: [HabitSnap] = []
    @State private var tasks: [Task] = []
    private let today = Day.today

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 18) {
                    tile(170, 170) { HabitWidgetView(entry: HabitEntry(date: Date(), today: today, habit: habits.first, config: config(.wall)), size: .systemSmall) }
                    tile(170, 170) { HabitWidgetView(entry: HabitEntry(date: Date(), today: today, habit: habits.dropFirst().first, config: config(.hero)), size: .systemSmall) }
                }
                tile(364, 170) { HabitWidgetView(entry: HabitEntry(date: Date(), today: today, habit: habits.dropFirst(2).first, config: config(.wall)), size: .systemMedium) }
                tile(364, 170) { ChecklistView(entry: ChecklistEntry(date: Date(), today: today, habits: habits, config: checklist()), size: .systemMedium) }
                tile(364, 170) { InboxWidgetView(entry: InboxEntry(date: Date(), today: today, tasks: tasks, config: inbox()), size: .systemMedium) }
            }
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity)
        }
        .background(LinearGradient(colors: [Color(hex: 0x8A7F70), Color(hex: 0x3B3631)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .task {
            let store = AppModel.shared.store
            habits = (try? await store.db.read { try Snapshot.habits($0, today: Day.today) }) ?? []
            tasks = (try? await store.db.read { try HabitStore.openTasks(in: $0) }) ?? []
        }
    }

    private func config(_ layout: HabitLayoutOption) -> HabitWidgetConfig { let c = HabitWidgetConfig(); c.layout = layout; c.look = look; return c }
    private func checklist() -> ChecklistConfig { let c = ChecklistConfig(); c.look = look; return c }
    private func inbox() -> InboxConfig { let c = InboxConfig(); c.look = look; return c }

    /// A widget-sized, widget-shaped box; the look's background comes from `containerBackground`,
    /// which only a real widget draws, so the gallery paints it the same way.
    private func tile<V: View>(_ w: CGFloat, _ h: CGFloat, @ViewBuilder _ v: () -> V) -> some View {
        v().padding(16).frame(width: w, height: h)
            .background(GalleryBackground(look: look))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct GalleryBackground: View {
    let look: WidgetLook
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = WidgetPalette.resolve(look, darkText: false, scheme: scheme)
        ZStack { p.background; if p.outlineCard { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(p.text, lineWidth: 1) } }
    }
}
#endif
