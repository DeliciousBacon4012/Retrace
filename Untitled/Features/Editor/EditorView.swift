import AppKit
import SwiftUI

/// The annotation editor: tools in the window toolbar, the image in the middle,
/// and a floating glass inspector with every setting for the selected mark or tool.
struct EditorView: View {
    @Bindable var document: EditorDocument
    let actions: EditorActions

    @AppStorage("editorShowsInspector") private var showsInspector = true
    @AppStorage(InspectorPlacement.storageKey) private var inspectorPlacement: InspectorPlacement = .right
    @AppStorage(EditorToolbarPosition.storageKey) private var toolbarPosition: EditorToolbarPosition = .top
    /// Where a floating inspector was dropped, as fractions of the room it can move in.
    @AppStorage("editorInspectorFloatX") private var floatX = 0.5
    @AppStorage("editorInspectorFloatY") private var floatY = 0.0
    /// The inspector's top left corner while it's being dragged.
    @State private var dragOrigin: CGPoint?
    @State private var dragStart: CGPoint?
    @State private var contentSize: CGSize = .zero
    @State private var inspectorWindow = InspectorWindowController()
    @AppStorage(EditorPalette.storageKey) private var palette: EditorPalette = .pastel
    @State private var exportItem: ExportItem?
    @State private var notice: EditorNotice?
    @State private var isReadingText = false
    @FocusState private var isCanvasFocused: Bool

    /// Small enough for a small screenshot, and wide enough that the toolbar keeps every tool
    /// on show instead of folding them into an overflow menu.
    static let minimumSize = CGSize(width: 820, height: 440)

    private var showsPanelInspector: Bool { showsInspector && inspectorPlacement != .window }
    private var paletteRoom: CGFloat { EditorToolPalette.thickness + Design.spacingL }
    private var dockedInspectorRoom: CGFloat { EditorInspector.width + Design.spacingL }

    /// Room kept clear on each side for docked panels, so they never cover the image. The
    /// image keeps its own margin inside, so it sits as far from a panel as from the edge.
    private var canvasInsets: EdgeInsets {
        let docked = showsPanelInspector && dragOrigin == nil
        return EdgeInsets(
            top: 0,
            leading: (toolbarPosition == .left ? paletteRoom : 0) + (docked && inspectorPlacement == .left ? dockedInspectorRoom : 0),
            bottom: toolbarPosition == .bottom ? paletteRoom : 0,
            trailing: (toolbarPosition == .right ? paletteRoom : 0) + (docked && inspectorPlacement == .right ? dockedInspectorRoom : 0)
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            canvas
                .padding(canvasInsets)

            if toolbarPosition != .top {
                toolPalette
            }

            if showsPanelInspector {
                let origin = dragOrigin ?? inspectorOrigin
                EditorInspector(document: document, chrome: .panel(grip: grip, maxHeight: contentSize.height - origin.y - Design.spacingL))
                    .offset(x: origin.x, y: origin.y)
                    .transition(.move(edge: inspectorPlacement == .left ? .leading : .trailing).combined(with: .opacity))
            }
        }
        .coordinateSpace(.named(EditorLayout.space))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { contentSize = $0 }
        .background(Color(nsColor: .underPageBackgroundColor))
        .animation(.panel, value: showsInspector)
        .animation(.panel, value: inspectorPlacement)
        .animation(.panel, value: toolbarPosition)
        .onChange(of: showsInspector, initial: true) { syncInspectorWindow(near: nil) }
        .onChange(of: inspectorPlacement) { syncInspectorWindow(near: nil) }
        .onDisappear { inspectorWindow.close() }
        .background { shortcutButtons }
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
        .toolbar { toolbar }
        .sheet(item: $exportItem) { item in
            ExportSheet(item: item, folder: actions.exportFolder, options: actions.exportOptions) { url in
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
        .focusable()
        .focused($isCanvasFocused)
        .focusEffectDisabled()
        .onAppear {
            isCanvasFocused = true
            document.onTextAreaChosen = { area in
                Task { await copyText(in: area) }
            }
        }
        .onKeyPress(phases: [.down, .repeat]) { press in
            handle(press)
        }
        .onCommand(#selector(NSResponder.selectAll(_:))) { document.selectAll() }
        .onDeleteCommand { document.deleteSelection() }
        .onChange(of: document.commandRequest) { _, request in
            guard let request else { return }
            document.clearCommandRequest()
            perform(request.command)
        }
        .onExitCommand {
            if document.isPickingTextArea {
                withAnimation(.response) { document.isPickingTextArea = false }
            } else if document.tool == .crop {
                document.cancelCrop()
            } else if document.editingTextID != nil {
                document.finishTextEditing()
            } else {
                document.select(nil)
            }
        }
    }

    // MARK: Panels

    /// The tools along the chosen edge, centered on the room the image has.
    private var toolPalette: some View {
        let docked = showsPanelInspector && dragOrigin == nil
        let leftInspector = docked && inspectorPlacement == .left ? dockedInspectorRoom : 0
        let rightInspector = docked && inspectorPlacement == .right ? dockedInspectorRoom : 0
        let alignment: Alignment = switch toolbarPosition {
        case .left: .leading
        case .right: .trailing
        default: .bottom
        }
        return EditorToolPalette(
            document: document,
            axis: toolbarPosition == .bottom ? .horizontal : .vertical,
            symbol: symbol(for:),
            position: $toolbarPosition
        )
        // Along a side, the tools keep the edge and a docked inspector moves in beside them;
        // along the bottom, they center between the docked panels.
        .padding(.leading, Design.spacingL + (toolbarPosition == .bottom ? leftInspector : 0))
        .padding(.trailing, Design.spacingL + (toolbarPosition == .bottom ? rightInspector : 0))
        .padding(.vertical, Design.spacingL)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .transition(.opacity.combined(with: .scale(0.9)))
    }

    /// The inspector's top left corner when it isn't being dragged.
    private var inspectorOrigin: CGPoint {
        let margin = Design.spacingL
        switch inspectorPlacement {
        case .left:
            return CGPoint(x: margin + (toolbarPosition == .left ? paletteRoom : 0), y: margin)
        case .floating:
            let roomX = max(contentSize.width - EditorInspector.width - margin * 2, 0)
            let roomY = max(contentSize.height - 200 - margin * 2, 0)
            return CGPoint(x: margin + roomX * min(max(floatX, 0), 1), y: margin + roomY * min(max(floatY, 0), 1))
        case .right, .window:
            let palette = toolbarPosition == .right ? paletteRoom : 0
            return CGPoint(x: contentSize.width - EditorInspector.width - margin - palette, y: margin)
        }
    }

    private var grip: InspectorGrip {
        InspectorGrip(placement: $inspectorPlacement, onDrag: dragInspector, onDrop: dropInspector)
    }

    private func dragInspector(_ value: DragGesture.Value) {
        let start = dragStart ?? inspectorOrigin
        dragStart = start
        dragOrigin = CGPoint(x: start.x + value.translation.width, y: max(start.y + value.translation.height, 0))
    }

    /// Dropped outside the window it gets a window of its own; near a side it docks there;
    /// anywhere else it floats where it was dropped.
    private func dropInspector(_ value: DragGesture.Value) {
        defer {
            dragOrigin = nil
            dragStart = nil
        }
        let mouse = NSEvent.mouseLocation
        if let window = NSApp.keyWindow, !window.frame.contains(mouse) {
            inspectorPlacement = .window
            syncInspectorWindow(near: mouse)
            return
        }
        let dockDistance: CGFloat = 80
        var placement = InspectorPlacement.floating
        if value.location.x < dockDistance {
            placement = .left
        } else if value.location.x > contentSize.width - dockDistance {
            placement = .right
        } else if let origin = dragOrigin {
            let margin = Design.spacingL
            let roomX = contentSize.width - EditorInspector.width - margin * 2
            let roomY = contentSize.height - 200 - margin * 2
            floatX = roomX > 0 ? Double((origin.x - margin) / roomX) : 0.5
            floatY = roomY > 0 ? Double((origin.y - margin) / roomY) : 0
            floatX = min(max(floatX, 0), 1)
            floatY = min(max(floatY, 0), 1)
        }
        withAnimation(.panel) {
            inspectorPlacement = placement
            dragOrigin = nil
        }
    }

    /// Shows or closes the inspector's own window to match the setting.
    private func syncInspectorWindow(near point: NSPoint?) {
        if showsInspector, inspectorPlacement == .window {
            inspectorWindow.onClose = { inspectorPlacement = .right }
            inspectorWindow.show(document: document, near: point)
        } else {
            inspectorWindow.close()
        }
    }

    @ViewBuilder
    private var layoutMenu: some View {
        Picker("Toolbar Position", selection: $toolbarPosition) {
            ForEach(EditorToolbarPosition.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
        }
        Picker("Inspector", selection: $inspectorPlacement) {
            ForEach(InspectorPlacement.allCases) { Text($0.title).tag($0) }
        }
    }

    /// Mark commands act on the selected marks; right-clicking a mark selects it first.
    @ViewBuilder
    private var canvasMenu: some View {
        Button("Copy Image") { actions.copy() }
        Button("Copy Text from Area…") { document.send(.copyText) }
        Divider()
        Group {
            Button("Duplicate") { document.duplicateSelection() }
            Button("Bring to Front") { document.bringSelectionToFront() }
            Button("Send to Back") { document.sendSelectionToBack() }
            Button("Delete", role: .destructive) { document.deleteSelection() }
        }
        .disabled(!document.hasSelection)
        Button("Select All") { document.selectAll() }
            .disabled(document.annotations.isEmpty)
        Divider()
        Button("Zoom to Fit") { document.zoomToFit() }
        Button("Actual Size") { document.zoomToActualSize() }
        Divider()
        layoutMenu
        Divider()
        Button("Save") { actions.save() }
        Button("Export…") { document.send(.export) }
    }

    private var canvas: some View {
        AnnotationCanvas(document: document)
            .contextMenu { canvasMenu }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { document.canvasSize = $0 }
            .overlay(alignment: .bottom) {
                EditorStatusBar(document: document)
                    .padding(.bottom, Design.spacingL)
            }
            .overlay(alignment: .top) {
                if document.isPickingTextArea {
                    EditorNoticeView(notice: Self.textAreaHint)
                        .padding(.top, Design.spacingL)
                        .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(0.9, anchor: .top)))
                } else if let notice {
                    EditorNoticeView(notice: notice)
                        .padding(.top, Design.spacingL)
                        .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(0.9, anchor: .top)))
                        .id(notice.id)
                }
            }
            .animation(.pop, value: notice?.id)
            .animation(.pop, value: document.isPickingTextArea)
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

        if toolbarPosition == .top {
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
                .contextMenu { layoutMenu }
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Toggle("Copy Text", systemImage: "text.viewfinder", isOn: textAreaBinding)
                .disabled(isReadingText)
                .symbolEffect(.pulse, isActive: isReadingText)
                .help("Copy text: drag over an area, or press Return for all of it (⇧⌘T)")
            Button("Copy", systemImage: "doc.on.doc") { actions.copy() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help("Copy the edited image (⇧⌘C)")
            Button("Save", systemImage: "square.and.arrow.down") { actions.save() }
                .keyboardShortcut("s", modifiers: .command)
                .help("Save (⌘S)")
            Button("Export", systemImage: "square.and.arrow.up") { startExport() }
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

    private func startExport() {
        if let image = actions.render() {
            exportItem = ExportItem(image: image, scale: document.scale, suggestedName: actions.suggestedName, hidesContent: document.hasRedactions)
        }
    }

    /// Carries out a command chosen in the menu bar.
    private func perform(_ command: EditorCommand) {
        switch command {
        case .export: startExport()
        case .copyText: if !isReadingText { textAreaBinding.wrappedValue = true }
        case .zoomIn: document.zoomIn(fitFactor: document.fitFactor)
        case .zoomOut: document.zoomOut(fitFactor: document.fitFactor)
        }
    }

    private static let textAreaHint = EditorNotice(
        symbolName: "text.viewfinder",
        title: String(localized: "Drag over text to copy it, or press Return for all")
    )

    private var textAreaBinding: Binding<Bool> {
        Binding {
            document.isPickingTextArea
        } set: { isOn in
            if isOn {
                notice = nil
                document.beginPickingTextArea()
            } else {
                document.isPickingTextArea = false
            }
        }
    }

    /// Reads the text in the edited image, or in one area of it, on device and puts it on
    /// the clipboard. Marks count: text under a redaction is never read.
    private func copyText(in area: CGRect? = nil) async {
        guard !isReadingText, let rendered = actions.render() else { return }
        var image = rendered
        if let area {
            guard let region = Self.region(area, croppedTo: document.cropRect, in: rendered),
                  let cropped = rendered.cropping(to: region)
            else {
                notice = EditorNotice(symbolName: "text.magnifyingglass", title: String(localized: "No text found"))
                return
            }
            image = cropped.upscaledForReading() ?? cropped
        }
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

    /// The area in the rendered image's pixels, with a little room around it so letters cut
    /// by the edge of the drag still read. The rendered image starts at the crop's corner.
    private static func region(_ area: CGRect, croppedTo crop: CGRect?, in image: CGImage) -> CGRect? {
        let origin = crop?.integral.origin ?? .zero
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let region = area.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -4, dy: -4).integral.intersection(bounds)
        return region.isEmpty ? nil : region
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
            Button("Copy Text") { textAreaBinding.wrappedValue = !document.isPickingTextArea }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(isReadingText)
            Button("Duplicate") { document.duplicateSelection() }
                .keyboardShortcut("d", modifiers: .command)
            Button("Bring to Front") { document.bringSelectionToFront() }
                .keyboardShortcut("]", modifiers: .command)
            Button("Send to Back") { document.sendSelectionToBack() }
                .keyboardShortcut("[", modifiers: .command)
            // ⌘= and ⌘+ are the same key; both are listed so either reading works.
            Button("Zoom In") { document.zoomIn(fitFactor: document.fitFactor) }
                .keyboardShortcut("=", modifiers: .command)
            Button("Zoom In") { document.zoomIn(fitFactor: document.fitFactor) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Zoom Out") { document.zoomOut(fitFactor: document.fitFactor) }
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

        if press.key == .return, document.isPickingTextArea {
            document.isPickingTextArea = false
            Task { await copyText() }
            return .handled
        }

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
        if let digit = Int(press.characters), let color = palette.color(forDigit: digit) {
            document.style.color = color
            return .handled
        }
        return .ignored
    }

    private func nudge(dx: CGFloat, dy: CGFloat) -> KeyPress.Result {
        guard document.hasSelection else { return .ignored }
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

    var body: some View {
        let fitFactor = document.fitFactor
        let zoom = document.currentZoom(fitFactor: fitFactor)
        let size = document.cropRect?.size ?? document.imageSize

        GlassEffectContainer(spacing: Design.spacingS) {
            HStack(spacing: Design.spacingS) {
                HStack(spacing: 2) {
                    Button("Zoom Out", systemImage: "minus") { document.zoomOut(fitFactor: fitFactor) }
                        .help("Zoom out (⌘−)")
                    ZoomScrubber(document: document)
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

/// The zoom percentage, which is also a control: press and drag right or up to zoom in,
/// left or down to zoom out, holding ⌥ for finer steps. It catches gently at Fit, 50 %,
/// 100 % and 200 % with a haptic tick. Click to fit, double-click for 100 %, or scroll
/// over it to zoom.
private struct ZoomScrubber: View {
    let document: EditorDocument

    private var fitFactor: CGFloat { document.fitFactor }

    /// Where the current drag is measured from. It moves when ⌥ is pressed or released
    /// mid-drag, so changing speed never makes the zoom jump.
    @State private var anchor: (zoom: CGFloat, distance: CGFloat, isFine: Bool)?
    /// The stop the zoom is resting on, so the haptic tick plays once per stop.
    @State private var restingStop: CGFloat?

    /// Points of drag that double or halve the zoom.
    private static let pointsPerDoubling: CGFloat = 140
    private static let fineSlowdown: CGFloat = 4
    /// How close, as a power of two, counts as on a stop. About 3 %.
    private static let catchRange: CGFloat = 0.04

    var body: some View {
        let zoom = document.currentZoom(fitFactor: fitFactor)

        Text(zoom, format: .percent.precision(.fractionLength(0)))
            .monospacedDigit()
            .frame(minWidth: 46)
            .contentTransition(.numericText(value: zoom))
            .padding(.vertical, 4)
            .contentShape(.rect)
            .pointerStyle(.columnResize)
            .onHover { document.isPointerOverZoomControl = $0 }
            .onDisappear { document.isPointerOverZoomControl = false }
            .gesture(drag.exclusively(before: taps))
            .background { ScrollWheelCatcher { scroll($0) } }
            .help("Drag to zoom. Click to fit (⌘9), double-click for 100 % (⌘0).")
            .accessibilityElement()
            .accessibilityLabel("Zoom")
            .accessibilityValue(Text(zoom, format: .percent.precision(.fractionLength(0))))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: document.zoomIn(fitFactor: fitFactor)
                case .decrement: document.zoomOut(fitFactor: fitFactor)
                @unknown default: break
                }
            }
    }

    private var taps: some Gesture {
        TapGesture(count: 2)
            .onEnded { document.zoomToActualSize() }
            .exclusively(before: TapGesture().onEnded { document.zoomToFit() })
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                // Right and up zoom in; SwiftUI measures down as positive.
                let distance = value.translation.width - value.translation.height
                let isFine = NSEvent.modifierFlags.contains(.option)
                let current = document.currentZoom(fitFactor: fitFactor)
                if anchor == nil {
                    anchor = (current, distance, isFine)
                } else if anchor?.isFine != isFine {
                    anchor = (current, distance, isFine)
                }
                guard let anchor else { return }
                let perDoubling = Self.pointsPerDoubling * (isFine ? Self.fineSlowdown : 1)
                set(anchor.zoom * pow(2, (distance - anchor.distance) / perDoubling))
            }
            .onEnded { _ in
                anchor = nil
                restingStop = nil
            }
    }

    /// Scrolling over the number zooms, like dragging does. Trackpads send many small
    /// steps and mouse wheels a few large ones, so each is scaled to feel the same.
    private func scroll(_ event: NSEvent) {
        let step = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 120 : event.scrollingDeltaY / 8
        let direction: CGFloat = event.isDirectionInvertedFromDevice ? -1 : 1
        set(document.currentZoom(fitFactor: fitFactor) * pow(2, step * direction))
        restingStop = nil
    }

    /// Sets the zoom straight away, catching on a nearby stop. Fit stays "fit", so it keeps
    /// fitting when the window is resized.
    private func set(_ proposed: CGFloat) {
        let fit = fitFactor * document.scale
        let clamped = min(max(proposed, 0.1), 8)
        let stops = [fit, 0.5, 1, 2]
        let stop = stops.min { abs(log2($0 / clamped)) < abs(log2($1 / clamped)) }
        if let stop, abs(log2(stop / clamped)) < Self.catchRange {
            if restingStop != stop {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                restingStop = stop
            }
            document.zoom = stop == fit ? nil : stop
            if stop == fit { document.pan = .zero }
        } else {
            restingStop = nil
            document.zoom = clamped
        }
    }
}

/// Passes scroll-wheel events over its area to `onScroll`, and lets every other event
/// through to the views underneath, so clicks and drags still reach them.
private struct ScrollWheelCatcher: NSViewRepresentable {
    let onScroll: (NSEvent) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onScroll = onScroll
    }

    final class CatcherView: NSView {
        var onScroll: ((NSEvent) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .scrollWheel ? super.hitTest(point) : nil
        }

        override func scrollWheel(with event: NSEvent) {
            onScroll?(event)
        }
    }
}
