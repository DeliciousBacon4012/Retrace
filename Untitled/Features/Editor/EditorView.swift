import AppKit
import SwiftUI

/// The annotation editor: tools in the window toolbar, the image in the middle,
/// and a glass inspector with every setting for the selected mark or tool.
struct EditorView: View {
    @Bindable var document: EditorDocument
    let actions: EditorActions

    @AppStorage("editorShowsInspector") private var showsInspector = true
    @State private var canvasSize: CGSize = .zero
    @FocusState private var isCanvasFocused: Bool

    private var fitFactor: CGFloat {
        CanvasLayout(imageSize: document.imageSize, scale: document.scale, zoom: nil, pan: .zero, in: canvasSize).fitFactor
    }

    var body: some View {
        AnnotationCanvas(document: document)
            .background(Color(nsColor: .underPageBackgroundColor))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { canvasSize = $0 }
            .overlay(alignment: .bottom) {
                EditorStatusBar(document: document, fitFactor: fitFactor)
                    .padding(.bottom, Design.spacingL)
            }
            .background { shortcutButtons }
            .frame(minWidth: 720, minHeight: 440)
            .inspector(isPresented: $showsInspector) {
                EditorInspector(document: document)
                    .inspectorColumnWidth(min: 250, ideal: 272, max: 340)
            }
            .toolbar { toolbar }
            .focusable()
            .focused($isCanvasFocused)
            .focusEffectDisabled()
            .onAppear { isCanvasFocused = true }
            .onKeyPress(phases: [.down, .repeat]) { press in
                handle(press)
            }
            .onDeleteCommand { document.deleteSelection() }
            .onExitCommand {
                if document.editingTextID != nil {
                    document.finishTextEditing()
                } else {
                    document.select(nil)
                }
            }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button("Undo", systemImage: "arrow.uturn.backward") { document.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!document.canUndo)
                .help("Undo (⌘Z)")
            Button("Redo", systemImage: "arrow.uturn.forward") { document.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!document.canRedo)
                .help("Redo (⇧⌘Z)")
        }

        ToolbarItem(placement: .principal) {
            Picker("Tool", selection: $document.tool) {
                ForEach(EditorTool.allCases) { tool in
                    Label(tool.title, systemImage: symbol(for: tool))
                        .help("\(tool.title) (\(String(tool.key).uppercased()))")
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button("Copy", systemImage: "doc.on.doc") { actions.copy() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help("Copy the edited image (⇧⌘C)")
            Button("Save", systemImage: "square.and.arrow.down") { actions.save() }
                .keyboardShortcut("s", modifiers: .command)
                .help("Save (⌘S)")
        }

        ToolbarSpacer(.fixed)

        ToolbarItem(placement: .primaryAction) {
            Button("Done") { actions.done() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Save, copy, and close (⌘↩)")
        }

        ToolbarItem(placement: .primaryAction) {
            Button("Inspector", systemImage: "sidebar.right") {
                withAnimation(.panel) { showsInspector.toggle() }
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .help("Show or hide the inspector (⌥⌘I)")
        }
    }

    /// The toolbar icon shows the variant each tool will draw, like a curved arrow or a mosaic.
    private func symbol(for tool: EditorTool) -> String {
        let style = document.style(for: tool)
        switch tool {
        case .arrow:
            return style.endHead == .none && style.startHead == .none ? "line.diagonal" : style.route.symbolName
        case .shape:
            return style.shape.symbolName
        case .redact:
            return style.redaction.symbolName
        default:
            return tool.symbolName
        }
    }

    /// Keyboard shortcuts that aren't on a visible control.
    private var shortcutButtons: some View {
        Group {
            Button("Duplicate") { document.duplicateSelection() }
                .keyboardShortcut("d", modifiers: .command)
            Button("Bring to Front") { document.bringSelectionToFront() }
                .keyboardShortcut("]", modifiers: .command)
            Button("Send to Back") { document.sendSelectionToBack() }
                .keyboardShortcut("[", modifiers: .command)
            Button("Zoom In") { document.zoomIn(fitFactor: fitFactor) }
                .keyboardShortcut("=", modifiers: .command)
            Button("Zoom Out") { document.zoomOut(fitFactor: fitFactor) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Zoom to Fit") { document.zoomToFit() }
                .keyboardShortcut("0", modifiers: .command)
            Button("Actual Size") { document.zoomToActualSize() }
                .keyboardShortcut("1", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard document.editingTextID == nil else { return .ignored }

        let step: CGFloat = press.modifiers.contains(.shift) ? 10 : 1
        switch press.key {
        case .leftArrow: return nudge(dx: -step, dy: 0)
        case .rightArrow: return nudge(dx: step, dy: 0)
        case .upArrow: return nudge(dx: 0, dy: -step)
        case .downArrow: return nudge(dx: 0, dy: step)
        default: break
        }

        guard press.phase == .down, press.modifiers.isEmpty || press.modifiers == .shift else { return .ignored }
        if let tool = EditorTool.allCases.first(where: { String($0.key) == press.characters.lowercased() }) {
            document.tool = tool
            return .handled
        }
        if let digit = Int(press.characters) {
            let index = digit == 0 ? 9 : digit - 1
            if RGBAColor.presets.indices.contains(index) {
                document.style.color = RGBAColor.presets[index]
                return .handled
            }
        }
        return .ignored
    }

    private func nudge(dx: CGFloat, dy: CGFloat) -> KeyPress.Result {
        guard document.selected != nil else { return .ignored }
        document.nudgeSelection(dx: dx, dy: dy)
        return .handled
    }
}

/// What the editor window does with the finished image.
struct EditorActions {
    var copy: () -> Void
    var save: () -> Void
    var done: () -> Void
}

/// Zoom controls and the image size, floating on glass at the bottom of the canvas.
private struct EditorStatusBar: View {
    let document: EditorDocument
    let fitFactor: CGFloat

    var body: some View {
        let zoom = document.currentZoom(fitFactor: fitFactor)
        let size = document.cropRect?.size ?? document.imageSize

        GlassEffectContainer(spacing: Design.spacingS) {
            HStack(spacing: Design.spacingS) {
                HStack(spacing: 2) {
                    Button("Zoom Out", systemImage: "minus") { document.zoomOut(fitFactor: fitFactor) }
                        .help("Zoom out (⌘−)")
                    Button {
                        document.zoomToFit()
                    } label: {
                        Text(zoom, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .frame(minWidth: 46)
                            .contentTransition(.numericText(value: zoom))
                    }
                    .help("Zoom to fit (⌘0)")
                    Button("Zoom In", systemImage: "plus") { document.zoomIn(fitFactor: fitFactor) }
                        .help("Zoom in (⌘=)")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.system(.callout, design: .monospaced).weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular.interactive(), in: .capsule)

                Text("\(Int(size.width)) × \(Int(size.height)) px")
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassEffect(.regular, in: .capsule)

                if document.cropRect != nil {
                    Button("Reset Crop", systemImage: "arrow.counterclockwise") { document.resetCrop() }
                        .buttonStyle(.glass)
                        .transition(.scale(0.8).combined(with: .opacity))
                }
            }
        }
        .animation(.response, value: document.cropRect == nil)
        .animation(.response, value: zoom)
    }
}
