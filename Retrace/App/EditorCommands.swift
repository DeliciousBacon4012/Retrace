import SwiftUI

/// Menu bar commands for the editor window in front. They're greyed out while any other
/// window has focus. Undo and Redo need nothing here: the editor window hands the standard
/// Edit menu its own undo history.
struct EditorCommands: Commands {
    let editors: EditorPresenter

    @AppStorage("editorShowsInspector") private var showsInspector = true
    @AppStorage(EditorPalette.storageKey) private var palette: EditorPalette = .pastel

    private var editor: EditorWindowController? { editors.active }
    private var document: EditorDocument? { editor?.editorDocument }

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Divider()
            Button("Save") { editor?.save() }
                .keyboardShortcut("s")
                .disabled(editor == nil)
            Button("Export…") { document?.send(.export) }
                .keyboardShortcut("e")
                .disabled(editor == nil)
            Button("Copy Edited Image") { editor?.copyImage() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(editor == nil)
            Button("Done Editing") { editor?.finish() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(editor == nil)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Text from Area…") { document?.send(.copyText) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(document == nil)
            Button("Duplicate") { document?.duplicateSelection() }
                .keyboardShortcut("d")
                .disabled(document?.hasSelection != true)
            Button("Bring to Front") { document?.bringSelectionToFront() }
                .keyboardShortcut("]")
                .disabled(document?.hasSelection != true)
            Button("Send to Back") { document?.sendSelectionToBack() }
                .keyboardShortcut("[")
                .disabled(document?.hasSelection != true)
        }

        CommandGroup(after: .toolbar) {
            Button(showsInspector ? "Hide Inspector" : "Show Inspector") { showsInspector.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(editor == nil)
            Divider()
            Button("Zoom In") { document?.send(.zoomIn) }
                .keyboardShortcut("+")
                .disabled(editor == nil)
            Button("Zoom Out") { document?.send(.zoomOut) }
                .keyboardShortcut("-")
                .disabled(editor == nil)
            Button("Actual Size") { document?.zoomToActualSize() }
                .keyboardShortcut("0")
                .disabled(editor == nil)
            Button("Zoom to Fit") { document?.zoomToFit() }
                .keyboardShortcut("9")
                .disabled(editor == nil)
            Divider()
        }

        // Tool letters work as single keys on the canvas. They aren't menu shortcuts here,
        // because a menu would take them from text being typed into a mark.
        CommandMenu("Tools") {
            Picker("Tool", selection: toolBinding) {
                ForEach(EditorTool.allCases) { tool in
                    Text("\(tool.title)  (\(String(tool.key).uppercased()))").tag(tool)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .disabled(document == nil)
            Divider()
            Picker("Palette", selection: $palette) {
                ForEach(EditorPalette.allCases) { Text($0.title).tag($0) }
            }
        }
    }

    private var toolBinding: Binding<EditorTool> {
        Binding {
            document?.tool ?? .select
        } set: { tool in
            withAnimation(.panel) { document?.tool = tool }
        }
    }
}
