import SwiftUI

/// How the annotation editor looks and behaves.
struct EditorSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppDependencies.self) private var dependencies

    @AppStorage(EditorPalette.storageKey) private var palette: EditorPalette = .pastel
    @AppStorage(EditorDocument.highlighterSnapsKey) private var snapsToText = true
    @AppStorage("editorShowsInspector") private var showsInspector = true
    @State private var confirmsReset = false

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Open after each screenshot", isOn: $settings.opensEditor)
                Toggle("Show the inspector", isOn: $showsInspector)
            } footer: {
                Text("When this is off, you can still open a screenshot in the editor from Quick Access or Recents.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Palette", selection: $palette) {
                    ForEach(EditorPalette.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                PaletteStrip(palette: palette)
            } header: {
                Text("Colors")
            } footer: {
                Text("Number keys 1 to 9 and 0 pick the first ten colors. The custom color picker is always there too.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Snap highlighter to text", isOn: $snapsToText)
            } footer: {
                Text("A highlighter stroke along a line of text covers its words neatly. The text is read on this Mac.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Tool styles") {
                    Button("Reset…") { confirmsReset = true }
                }
            } footer: {
                Text("Each tool remembers its last color, size, and style.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .animation(.response, value: palette)
        .confirmationDialog("Reset every tool to its original style?", isPresented: $confirmsReset) {
            Button("Reset Tool Styles", role: .destructive) {
                dependencies.editor.resetToolStyles()
            }
        } message: {
            Text("Marks you've already drawn keep their look.")
        }
    }
}

/// The palette's swatches in a row, so the choice is visible before opening the editor.
private struct PaletteStrip: View {
    let palette: EditorPalette

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(zip(palette.colors, palette.names).enumerated()), id: \.offset) { _, swatch in
                Circle()
                    .fill(swatch.0.swiftUIColor)
                    .overlay { Circle().strokeBorder(.separator, lineWidth: 1) }
                    .frame(width: 18, height: 18)
                    .help(swatch.1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(palette.names.formatted(.list(type: .and)))
    }
}

#if DEBUG
#Preview {
    let dependencies = AppDependencies.preview()
    EditorSettingsView()
        .environment(dependencies)
        .environment(dependencies.settings)
        .frame(width: 520)
}
#endif
