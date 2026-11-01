import AppKit
import SwiftUI

/// The annotation editor: tools in the window toolbar, the image in the middle,
/// and a floating glass inspector with every setting for the selected mark or tool.
struct EditorView: View {
    @Bindable var document: EditorDocument
    let actions: EditorActions

    @AppStorage("editorShowsInspector") private var showsInspector = true
    @State private var exportItem: ExportItem?
    @State private var canvasSize: CGSize = .zero
    @State private var notice: EditorNotice?
    @State private var isReadingText = false
    @FocusState private var isCanvasFocused: Bool

    private var fitFactor: CGFloat {
        CanvasLayout(imageSize: document.imageSize, scale: document.scale, zoom: nil, pan: .zero, focus: document.visibleRect, in: canvasSize).fitFactor
    }

    /// Room kept clear on the right for the floating inspector, so it never covers the image.
    private var inspectorInset: CGFloat {
        showsInspector ? EditorInspector.width + Design.spacingL * 2 : 0
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            canvas
                .padding(.trailing, inspectorInset)

            if showsInspector {
                EditorInspector(document: document)
                    .padding(.vertical, Design.spacingL)
                    .padding(.trailing, Design.spacingL)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .animation(.panel, value: showsInspector)
        .background { shortcutButtons }
        .frame(minWidth: 720, minHeight: 440)
        .toolbar { toolbar }
        .sheet(item: $exportItem) { item in
            ExportSheet(item: item, folder: actions.exportFolder, options: actions.exportOptions) { url in
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
        .focusable()
        .focused($isCanvasFocused)
        .focusEffectDisabled()
        .onAppear { isCanvasFocused = true }
        .onKeyPress(phases: [.down, .repeat]) { press in
            handle(press)
        }
        .onDeleteCommand { document.deleteSelection() }
        .onExitCommand {
            if document.tool == .crop {
                document.cancelCrop()
            } else if document.editingTextID != nil {
                document.finishTextEditing()
            } else {
                document.select(nil)
            }
        }
    }

    private var canvas: some View {
        AnnotationCanvas(document: document)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { canvasSize = $0 }
            .overlay(alignment: .bottom) {
                EditorStatusBar(document: document, fitFactor: fitFactor)
                    .padding(.bottom, Design.spacingL)
            }
            .overlay(alignment: .top) {
                if let notice {
                    EditorNoticeView(notice: notice)
                        .padding(.top, Design.spacingL)
                        .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(0.9, anchor: .top)))
                        .id(notice.id)
                }
            }
            .animation(.pop, value: notice?.id)
            .task(id: notice?.id) {
                guard notice != nil else { return }
                try? await Task.sleep(for: .seconds(2.4))
                guard !Task.isCancelled else { return }
                notice = nil
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
            Button("Copy Text", systemImage: "text.viewfinder") {
                Task { await copyText() }
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(isReadingText)
            .symbolEffect(.pulse, isActive: isReadingText)
            .help("Copy the text in this image (⇧⌘T)")
            Button("Copy", systemImage: "doc.on.doc") { actions.copy() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help("Copy the edited image (⇧⌘C)")
            Button("Save", systemImage: "square.and.arrow.down") { actions.save() }
                .keyboardShortcut("s", modifiers: .command)
                .help("Save (⌘S)")
            Button("Export", systemImage: "square.and.arrow.up") {
                if let image = actions.render() {
                    exportItem = ExportItem(image: image, scale: document.scale, suggestedName: actions.suggestedName, hidesContent: document.hasRedactions)
                }
            }
            .keyboardShortcut("e", modifiers: .command)
            .help("Export with a different format, size, or quality (⌘E)")
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
                showsInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .help("Show or hide the inspector (⌥⌘I)")
        }
    }

    /// Reads the text in the edited image on device and puts it on the clipboard.
    private func copyText() async {
        guard let image = actions.render() else { return }
        isReadingText = true
        defer { isReadingText = false }
        do {
            let content = try await TextRecognizer.recognize(image)
            let text = content.lines.isEmpty ? content.codes.joined(separator: "\n") : content.text
            guard !text.isEmpty else {
                notice = EditorNotice(symbolName: "text.magnifyingglass", title: String(localized: "No text found"))
                return
            }
            actions.copyText(text)
            let count = content.lines.count
            let title = switch count {
            case 0: String(localized: "Copied code contents")
            case 1: String(localized: "Copied 1 line")
            default: String(localized: "Copied \(count) lines")
            }
            notice = EditorNotice(symbolName: "doc.on.clipboard", title: title)
        } catch {
            ErrorPresenter.present(error)
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
            // ⌘= and ⌘+ are the same key; both are listed so either reading works.
            Button("Zoom In") { document.zoomIn(fitFactor: fitFactor) }
                .keyboardShortcut("=", modifiers: .command)
            Button("Zoom In") { document.zoomIn(fitFactor: fitFactor) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Zoom Out") { document.zoomOut(fitFactor: fitFactor) }
                .keyboardShortcut("-", modifiers: .command)
            // Preview's keys: ⌘0 for actual size and ⌘9 to fit. ⌘1 and ⌘2 belong to the
            // main window's pages.
            Button("Actual Size") { document.zoomToActualSize() }
                .keyboardShortcut("0", modifiers: .command)
            Button("Zoom to Fit") { document.zoomToFit() }
                .keyboardShortcut("9", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard document.editingTextID == nil else { return .ignored }

        if press.key == .return, document.tool == .crop {
            document.commitCrop()
            return .handled
        }

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
    /// The finished image, for exporting.
    var render: () -> CGImage?
    var copyText: (String) -> Void
    var exportFolder: URL
    var exportOptions: ExportOptions
    var suggestedName: String
}

/// A short confirmation that floats in at the top of the canvas, then fades.
struct EditorNotice: Equatable {
    let id = UUID()
    var symbolName: String
    var title: String
}

private struct EditorNoticeView: View {
    let notice: EditorNotice

    var body: some View {
        Label(notice.title, systemImage: notice.symbolName)
            .font(.callout.weight(.medium))
            .symbolRenderingMode(.hierarchical)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: .capsule)
    }
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
                    .help("Zoom to fit (⌘9)")
                    Button("Zoom In", systemImage: "plus") { document.zoomIn(fitFactor: fitFactor) }
                        .help("Zoom in (⌘+)")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.system(.callout, design: .monospaced).weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular.interactive(), in: .capsule)

                Text(verbatim: "\(Int(size.width)) × \(Int(size.height)) px")
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassEffect(.regular, in: .capsule)

                if document.tool == .crop {
                    Button("Cancel") { document.cancelCrop() }
                        .buttonStyle(.glass)
                        .help("Put the crop back (Esc)")
                        .transition(.scale(0.8).combined(with: .opacity))
                    Button("Crop", systemImage: "checkmark") { document.commitCrop() }
                        .buttonStyle(.glassProminent)
                        .help("Apply the crop (Return)")
                        .transition(.scale(0.8).combined(with: .opacity))
                } else if document.cropRect != nil {
                    Button("Reset Crop", systemImage: "arrow.counterclockwise") { document.resetCrop() }
                        .buttonStyle(.glass)
                        .transition(.scale(0.8).combined(with: .opacity))
                }
            }
        }
        .animation(.response, value: document.tool == .crop)
        .animation(.response, value: document.cropRect == nil)
        .animation(.response, value: zoom)
    }
}
