import AppKit
import SwiftUI

/// The annotation editor: tools and style in the window toolbar, the image below.
struct EditorView: View {
    @Bindable var document: EditorDocument
    let actions: EditorActions

    @State private var showsStyle = false

    var body: some View {
        AnnotationCanvas(document: document)
            .background(.background.secondary)
            .frame(minWidth: 560, minHeight: 380)
            .toolbar { toolbar }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(phases: .down) { press in
                handle(press)
            }
            .onDeleteCommand { document.deleteSelection() }
            .onExitCommand {
                if document.editingTextID != nil {
                    document.finishTextEditing()
                } else {
                    document.selectedID = nil
                }
            }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button("Undo", systemImage: "arrow.uturn.backward") { document.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!document.canUndo)
                .help("Undo")
            Button("Redo", systemImage: "arrow.uturn.forward") { document.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!document.canRedo)
                .help("Redo")
        }

        ToolbarItem(placement: .principal) {
            Picker("Tool", selection: $document.tool) {
                ForEach(AnnotationTool.allCases) { tool in
                    Label(tool.title, systemImage: tool.symbolName)
                        .help("\(tool.title) (\(String(tool.key).uppercased()))")
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
        }

        ToolbarItem {
            Button {
                showsStyle.toggle()
            } label: {
                Label {
                    Text("Style")
                } icon: {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(Color(.sRGB, red: document.color.red, green: document.color.green, blue: document.color.blue))
                }
            }
            .help("Color and line width")
            .popover(isPresented: $showsStyle, arrowEdge: .bottom) {
                StylePopover(document: document)
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button("Copy", systemImage: "doc.on.doc") { actions.copy() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help("Copy the edited image (⇧⌘C)")
            Button("Save", systemImage: "square.and.arrow.down") { actions.save() }
                .keyboardShortcut("s", modifiers: .command)
                .help("Save (⌘S)")
        }

        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { actions.done() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Save, copy, and close (⌘↩)")
        }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard document.editingTextID == nil, press.modifiers.isEmpty || press.modifiers == .shift else { return .ignored }
        if let tool = AnnotationTool.allCases.first(where: { String($0.key) == press.characters.lowercased() }) {
            document.tool = tool
            return .handled
        }
        if let digit = Int(press.characters), (1...8).contains(digit) {
            document.color = RGBAColor.presets[digit - 1]
            return .handled
        }
        return .ignored
    }
}

/// What the editor window does with the finished image.
struct EditorActions {
    var copy: () -> Void
    var save: () -> Void
    var done: () -> Void
}

/// Color swatches, line width, and fill.
private struct StylePopover: View {
    @Bindable var document: EditorDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach(Array(RGBAColor.presets.enumerated()), id: \.offset) { index, preset in
                    Button {
                        document.color = preset
                    } label: {
                        Circle()
                            .fill(Color(.sRGB, red: preset.red, green: preset.green, blue: preset.blue))
                            .frame(width: 22, height: 22)
                            .overlay {
                                Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 1)
                            }
                            .overlay {
                                if preset == document.color {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(preset.prefersLightContent ? .white : .black)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help("Color \(index + 1)")
                    .accessibilityLabel("Color \(index + 1)")
                }
                ColorPicker("Custom Color", selection: customColor, supportsOpacity: false)
                    .labelsHidden()
            }

            LabeledContent("Width") {
                Slider(value: $document.lineWidth, in: 1...20, step: 1)
                    .frame(width: 180)
            }

            Toggle("Fill shapes", isOn: $document.fillsShapes)
        }
        .padding(16)
    }

    private var customColor: Binding<Color> {
        Binding {
            Color(.sRGB, red: document.color.red, green: document.color.green, blue: document.color.blue)
        } set: { newValue in
            guard let resolved = NSColor(newValue).usingColorSpace(.sRGB) else { return }
            document.color = RGBAColor(
                red: Double(resolved.redComponent),
                green: Double(resolved.greenComponent),
                blue: Double(resolved.blueComponent)
            )
        }
    }
}
