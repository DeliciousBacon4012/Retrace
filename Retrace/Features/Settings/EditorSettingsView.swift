import SwiftUI

/// How the annotation editor looks and behaves.
struct EditorSettingsView: View {
    @AppStorage(EditorBlurQuality.storageKey) private var blurQuality: EditorBlurQuality = .quality
    @AppStorage(EditorOpenPlacement.storageKey) private var openPlacement: EditorOpenPlacement = .tab
    @Environment(SettingsStore.self) private var settings
    @Environment(AppDependencies.self) private var dependencies

    @AppStorage(EditorPalette.storageKey) private var palette: EditorPalette = .pastel
    @AppStorage(EditorPalette.customColorsStorageKey) private var customPaletteData = EditorPalette.defaultCustomColorsData
    @AppStorage(EditorDocument.highlighterSnapsKey) private var snapsToText = true
    @AppStorage("editorShowsInspector") private var showsInspector = true
    @AppStorage(InspectorPlacement.storageKey) private var inspectorPlacement: InspectorPlacement = .right
    @AppStorage(EditorToolbarPosition.storageKey) private var toolbarPosition: EditorToolbarPosition = .top
    @State private var confirmsReset = false
    @State private var editsCustomPalette = false

    var body: some View {
        @Bindable var settings = settings

        Group {
            Section {
                Toggle("Open after each screenshot", isOn: $settings.opensEditor)
                Toggle("Show the inspector", isOn: $showsInspector)
                Picker("Inspector", selection: $inspectorPlacement) {
                    ForEach(InspectorPlacement.allCases) { Text($0.title).tag($0) }
                }
                .disabled(!showsInspector)
                Picker("Tools", selection: $toolbarPosition) {
                    ForEach(EditorToolbarPosition.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                }
            } footer: {
                Text("Drag the inspector by the dots on top: drop it at a side to dock it, or outside the window to give it its own. Right-click the tools to move them to another edge. When opening after each screenshot is off, you can still open one from Quick Access or Library.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Palette", selection: $palette) {
                    ForEach(EditorPalette.allCases) { Text($0.title).tag($0) }
                }
                .capsuleSegmentedStyle()
                PaletteStrip(palette: palette, customColors: EditorPalette.customColors(from: customPaletteData))
                if palette == .custom {
                    Button("Edit Custom Palette…", systemImage: "slider.horizontal.3") {
                        editsCustomPalette = true
                    }
                }
            } header: {
                Text("Colors")
            } footer: {
                Text("Number keys 1 to 9 and 0 pick the first ten colors. A custom color picker is always available; choose Custom to edit a saved palette.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Open images in", selection: $openPlacement) {
                    ForEach(EditorOpenPlacement.allCases) { Text($0.title).tag($0) }
                }
                .capsuleSegmentedStyle()
            } footer: {
                Text("If the Editor tab has unsaved changes, the next image opens in a new window, so your work is never replaced. You can also right-click a Library item and choose Open in New Window.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Blur preview", selection: $blurQuality) {
                    ForEach(EditorBlurQuality.allCases) { Text($0.title).tag($0) }
                }
                .capsuleSegmentedStyle()
            } footer: {
                Text("Fast keeps blur and Spotlight responsive on large images. Saved and exported images always use the full-quality blur.")
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
        .animation(.response, value: palette)
        .confirmationDialog("Reset every tool to its original style?", isPresented: $confirmsReset) {
            Button("Reset Tool Styles", role: .destructive) {
                dependencies.editor.resetToolStyles()
            }
        } message: {
            Text("Marks you've already drawn keep their look.")
        }
        .sheet(isPresented: $editsCustomPalette) {
            EditorPaletteEditor(encodedColors: $customPaletteData)
        }
    }
}

/// The palette's swatches in a row, so the choice is visible before opening the editor.
private struct PaletteStrip: View {
    let palette: EditorPalette
    let customColors: [RGBAColor]

    private var colors: [RGBAColor] { palette.colors(custom: customColors) }
    private var names: [String] { palette.names }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(zip(colors, names).enumerated()), id: \.offset) { _, swatch in
                Circle()
                    .fill(swatch.0.swiftUIColor)
                    .overlay { Circle().strokeBorder(.separator, lineWidth: 1) }
                    .frame(width: 18, height: 18)
                    .help(swatch.1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(names.formatted(.list(type: .and)))
    }
}

#if DEBUG
#Preview {
    let dependencies = AppDependencies.preview()
    EditorSettingsView()
        .environment(dependencies)
        .environment(dependencies.settings)
        .settingsPage()
}
#endif
