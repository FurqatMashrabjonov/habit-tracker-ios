import SwiftUI
import HabitData
import HabitDesign

/// First version of the editor: a name and an icon. Schedule, reminder, cue and templates come with
/// the full Edit sheet.
struct NewHabitSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var name = ""
    @State private var icon = "drop"
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Name", text: $name)
                        .font(Type.bodyLarge)
                        .focused($focused)
                        .padding(14)
                        .background(palette.tile, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                        .onChange(of: name) { _, v in if v.count > nameMax { name = String(v.prefix(nameMax)) } }
                    Text("ICON").font(Type.labelMedium).foregroundStyle(palette.dim).padding(.leading, 4)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                        ForEach(habitIconKeys, id: \.self) { key in
                            Button { icon = key } label: {
                                Image("Icons/\(key)").resizable().frame(width: 22, height: 22)
                                    .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                                    .foregroundStyle(key == icon ? palette.onInk : palette.ink)
                                    .background(key == icon ? palette.ink : palette.tile, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .animation(.easeOut(duration: 0.15), value: icon)
                        }
                    }
                }
                .padding(16)
            }
            .background(palette.surfaceLow)
            .navigationTitle("New habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { model.add(name: name.trimmingCharacters(in: .whitespaces), icon: icon); dismiss() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(Radius.sheet)
        .onAppear { focused = true }
    }
}
