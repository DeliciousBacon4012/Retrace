import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Observation
import OSLog
import SwiftUI

/// The state of one editor window: the screenshot, its marks, the selection, the crop,
/// and undo history. All positions are in image pixels.
@Observable
final class EditorDocument {
    let image: CGImage
    /// Pixels per point of the original capture, used to size new marks sensibly.
    let scale: CGFloat
    private(set) var fileURL: URL?

    private(set) var annotations: [Annotation] = []

    /// True when any mark hides part of the image, so every copy that leaves the editor
    /// must be the covered version, with nothing extra in the file.
    var hasRedactions: Bool { annotations.contains { $0.tool == .redact } }
    private(set) var cropRect: CGRect?
    private(set) var selectedID: Annotation.ID?
    /// The text mark being typed into, if any.
    private(set) var editingTextID: Annotation.ID?
    /// A mark being drawn right now, not yet in `annotations`.
    private(set) var draft: Annotation?
    private(set) var hasUnsavedChanges = false

    var tool: EditorTool = .arrow {
        didSet {
            guard tool != oldValue else { return }
            finishTextEditing()
            isPickingTextArea = false
            if tool == .crop {
                select(nil)
                toolBeforeCrop = oldValue
                cropBeforeEditing = cropRect
                zoom = nil
                pan = .zero
            } else if oldValue == .crop {
                zoom = nil
                pan = .zero
            }
            if tool == .redact {
                let style = style(for: .redact)
                prepareRedaction(style.redaction, around: style.strength)
            }
            if tool == .highlighter {
                prepareTextLines()
            }
        }
    }

    // MARK: Menu commands

    /// A menu bar command for this editor that the editor view carries out, because it
    /// needs the view's size or presents a sheet.
    private(set) var commandRequest: EditorCommandRequest?

    func send(_ command: EditorCommand) {
        commandRequest = EditorCommandRequest(command: command)
    }

    func clearCommandRequest() {
        commandRequest = nil
    }

    // MARK: Highlighter snapping

    /// The preference for snapping highlighter strokes to lines of text. On unless turned off.
    static let highlighterSnapsKey = "editorHighlighterSnaps"
    static var highlighterSnapsToText: Bool {
        UserDefaults.standard.object(forKey: highlighterSnapsKey) as? Bool ?? true
    }

    /// Lines and words in the screenshot, read on device the first time the highlighter is
    /// picked. Until they arrive, strokes stay freehand.
    @ObservationIgnored private var textLines: [TextLine]?
    @ObservationIgnored private var isReadingTextLines = false
    /// The highlighter stroke as drawn, before any snapping.
    @ObservationIgnored private var rawHighlight: [CGPoint] = []

    func prepareTextLines() {
        guard textLines == nil, !isReadingTextLines, Self.highlighterSnapsToText else { return }
        isReadingTextLines = true
        let image = image
        Task { [weak self] in
            let lines = (try? await TextRecognizer.textLayout(in: image)) ?? []
            self?.textLines = lines
            self?.isReadingTextLines = false
        }
    }

    // MARK: Text area

    /// True while the person drags out an area to copy text from (⇧⌘T).
    /// Drawing, selecting, and cropping pause until the area is chosen or the mode is left.
    var isPickingTextArea = false {
        didSet {
            guard isPickingTextArea != oldValue else { return }
            textArea = nil
            textAreaStart = nil
        }
    }

    /// The area being dragged out, in image pixels.
    private(set) var textArea: CGRect?
    @ObservationIgnored private var textAreaStart: CGPoint?
    /// Called with the chosen area, in image pixels, when the drag ends.
    @ObservationIgnored var onTextAreaChosen: ((CGRect) -> Void)?

    func beginPickingTextArea() {
        commitCrop()
        finishTextEditing()
        isPickingTextArea = true
    }

    func textAreaDown(at point: CGPoint) {
        let start = clampedToVisible(point)
        textAreaStart = start
        textArea = CGRect(origin: start, size: .zero)
    }

    func textAreaDragged(to point: CGPoint) {
        guard let start = textAreaStart else { return }
        let end = clampedToVisible(point)
        textArea = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// A click or a tiny drag keeps the mode on, so a slip doesn't end it.
    func textAreaUp() {
        textAreaStart = nil
        guard let area = textArea, area.width >= 4, area.height >= 4 else {
            textArea = nil
            return
        }
        isPickingTextArea = false
        onTextAreaChosen?(area)
    }

    private func clampedToVisible(_ point: CGPoint) -> CGPoint {
        let bounds = cropRect ?? CGRect(origin: .zero, size: imageSize)
        return CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    /// While cropping, the whole image shows so the crop can grow; otherwise only the crop does.
    var visibleRect: CGRect? { tool == .crop ? nil : cropRect }

    @ObservationIgnored private var toolBeforeCrop: EditorTool = .arrow
    @ObservationIgnored private var cropBeforeEditing: CGRect?

    /// Return in the crop tool: keep the crop and go back to the previous tool.
    func commitCrop() {
        guard tool == .crop else { return }
        withAnimation(.panel) { tool = toolBeforeCrop == .crop ? .select : toolBeforeCrop }
    }

    /// Escape in the crop tool: put the crop back the way it was and leave the tool.
    func cancelCrop() {
        guard tool == .crop else { return }
        if cropRect != cropBeforeEditing {
            pushUndo(snapshot, named: String(localized: "Crop"))
            cropRect = cropBeforeEditing
        }
        withAnimation(.panel) { tool = toolBeforeCrop == .crop ? .select : toolBeforeCrop }
    }

    /// The crop as a box, so it can use the same handles as rectangles.
    var cropBox: Annotation? {
        guard let cropRect else { return nil }
        var box = Annotation(tool: .shape, at: cropRect.origin, style: MarkStyle.defaults(for: .shape, scale: scale))
        box.end = CGPoint(x: cropRect.maxX, y: cropRect.maxY)
        return box
    }

    /// The zoom, as a fraction of the image's actual size. `nil` fits the image to the window.
    var zoom: CGFloat?
    /// Whether the pointer is over the zoom percentage, which scrolls to zoom; the canvas
    /// leaves those scroll events alone.
    @ObservationIgnored var isPointerOverZoomControl = false
    /// How far the image is scrolled from center, in view points.
    var pan: CGSize = .zero

    /// The last style used with each tool, so new marks look like the previous one.
    private(set) var toolStyles: [EditorTool: MarkStyle]

    /// The window's undo manager, so Edit › Undo, ⌘Z, and ⇧⌘Z all work on marks,
    /// with action names like "Undo Move".
    @ObservationIgnored let undoManager: UndoManager = {
        let manager = UndoManager()
        manager.levelsOfUndo = 200
        return manager
    }()
    /// Bumped on every history change so `canUndo` and `canRedo` refresh the toolbar.
    private var historyVersion = 0
    @ObservationIgnored private var gesture: Gesture?
    @ObservationIgnored private var gestureSnapshot: Snapshot?
    @ObservationIgnored private var textEditSnapshot: Snapshot?
    @ObservationIgnored private var lastStyleEdit: (id: Annotation.ID?, tool: EditorTool, date: Date)?
    /// Blurred and pixelated copies of the screenshot, each as big as the screenshot itself
    /// (about 60 MB at 5K). Only a few are kept: see `keepRedactionLayer`.
    @ObservationIgnored private var redactionLayers: [String: CGImage] = [:]
    /// Layer keys, least recently used first.
    @ObservationIgnored private var redactionLayerUse: [String] = []
    @ObservationIgnored private var pendingRedactions: Set<String> = []
    /// Bumped when a background redaction layer is ready, so the canvas redraws with it.
    private var redactionVersion = 0
    /// Saves tool styles shortly after the last change, not on every slider tick.
    @ObservationIgnored private var styleSaveTask: Task<Void, Never>?
    @ObservationIgnored private let styleStore: EditorStyleStore

    private struct Snapshot: Equatable {
        let annotations: [Annotation]
        let cropRect: CGRect?
    }

    private enum Gesture {
        case drawing
        case moving(last: CGPoint)
        case handle(MarkHandle)
        case cropping(origin: CGPoint)
        case movingCrop(last: CGPoint)
        case cropHandle(MarkHandle)
    }

    init(image: CGImage, scale: CGFloat, fileURL: URL?, annotations: [Annotation] = [], styleStore: EditorStyleStore = EditorStyleStore()) {
        self.image = image
        self.scale = max(scale, 1)
        self.fileURL = fileURL
        self.annotations = annotations
        self.styleStore = styleStore
        toolStyles = styleStore.load(scale: max(scale, 1))
        observeUndoManager()
    }

    /// Edit › Undo and ⌘Z go straight to the undo manager, so listen for its changes to keep
    /// the toolbar's Undo and Redo buttons current.
    private func observeUndoManager() {
        let names: [Notification.Name] = [.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange, .NSUndoManagerDidCloseUndoGroup]
        for name in names {
            NotificationCenter.default.addObserver(forName: name, object: undoManager, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.historyVersion += 1 }
            }
        }
    }

    var imageSize: CGSize { CGSize(width: image.width, height: image.height) }
    var canUndo: Bool {
        _ = historyVersion
        return undoManager.canUndo
    }

    var canRedo: Bool {
        _ = historyVersion
        return undoManager.canRedo
    }
    var selected: Annotation? { annotations.first { $0.id == selectedID } }

    /// The tool whose settings the inspector shows: the selected mark's, or the current tool's.
    var inspectedTool: EditorTool { selected?.tool ?? tool }

    /// The style the inspector edits. Changing it restyles the selected mark and becomes
    /// that tool's style for the next mark.
    var style: MarkStyle {
        get { selected?.style ?? style(for: tool) }
        set { applyStyle(newValue) }
    }

    func style(for tool: EditorTool) -> MarkStyle {
        toolStyles[tool] ?? MarkStyle.defaults(for: tool, scale: scale)
    }

    /// A binding that shows a size stored in pixels as points, for the inspector.
    func pointBinding(_ keyPath: WritableKeyPath<MarkStyle, CGFloat>) -> Binding<Double> {
        let scale = scale
        return Binding {
            Double(self.style[keyPath: keyPath] / scale)
        } set: { newValue in
            self.style[keyPath: keyPath] = CGFloat(newValue) * scale
        }
    }

    /// Puts the inspected tool back to its original look, including the selected mark.
    func resetStyle() {
        let tool = inspectedTool
        style = MarkStyle.defaults(for: tool, scale: scale)
    }

    // MARK: Pointer input, in image pixels

    /// Starts a click or drag. `tolerance` is how far, in pixels, a click may miss a thin mark.
    func pointerDown(at point: CGPoint, tolerance: CGFloat, clickCount: Int) {
        finishTextEditing()
        gestureSnapshot = snapshot
        if tool == .crop {
            if let box = cropBox, let handle = MarkHandle.hit(at: point, on: box, tolerance: tolerance * 1.8) {
                gesture = .cropHandle(handle)
            } else if let cropRect, cropRect.contains(point) {
                gesture = .movingCrop(last: point)
            } else {
                gesture = .cropping(origin: clamp(point))
            }
            return
        }

        // A handle on the selected mark wins over everything else.
        if let mark = selected, let handle = MarkHandle.hit(at: point, on: mark, tolerance: tolerance * 1.5) {
            gesture = .handle(handle)
            return
        }

        if let hit = annotations.last(where: { $0.contains(point, tolerance: tolerance) }) {
            if hit.tool == .text, clickCount >= 2 || tool == .text {
                beginEditing(hit.id)
                gesture = nil
                return
            }
            select(hit.id)
            gesture = .moving(last: point)
            return
        }

        select(nil)
        guard tool.draws else {
            gesture = nil
            return
        }

        var mark = Annotation(tool: tool, at: point, style: style(for: tool))
        switch tool {
        case .text:
            textEditSnapshot = gestureSnapshot
            withAnimation(.response) { annotations.append(mark) }
            hasUnsavedChanges = true
            select(mark.id)
            editingTextID = mark.id
            gesture = nil
        case .counter:
            mark.number = (annotations.filter { $0.tool == .counter }.map(\.number).max() ?? 0) + 1
            pushUndo(gestureSnapshot, named: String(localized: "Add Number"))
            withAnimation(.pop) { annotations.append(mark) }
            select(mark.id)
            gesture = .moving(last: point)
            gestureSnapshot = nil
        default:
            if tool == .highlighter {
                prepareTextLines()
                rawHighlight = mark.points
            }
            draft = mark
            gesture = .drawing
        }
    }

    /// `freehand` (⌥ held) keeps a highlighter stroke from snapping to text.
    func pointerDragged(to point: CGPoint, constrained: Bool, freehand: Bool = false) {
        switch gesture {
        case .drawing:
            guard var mark = draft else { return }
            switch mark.tool {
            case .pen:
                if let last = mark.points.last, hypot(point.x - last.x, point.y - last.y) >= 1.5 {
                    mark.points.append(point)
                }
            case .highlighter:
                if let last = rawHighlight.last, hypot(point.x - last.x, point.y - last.y) >= 1.5 {
                    rawHighlight.append(point)
                }
                let drawnWidth = style(for: .highlighter).lineWidth
                if constrained, let first = rawHighlight.first {
                    // Shift draws one perfectly straight stroke.
                    mark.points = [first, Geometry.snapped(from: first, to: point)]
                    mark.style.lineWidth = drawnWidth
                } else if !freehand, Self.highlighterSnapsToText, let lines = textLines,
                          let band = HighlightSnapping.band(for: rawHighlight, lines: lines) {
                    mark.points = [band.start, band.end]
                    mark.style.lineWidth = band.thickness
                } else {
                    mark.points = rawHighlight
                    mark.style.lineWidth = drawnWidth
                }
            case .arrow:
                mark.end = constrained ? Geometry.snapped(from: mark.start, to: point) : point
                if mark.style.route == .curved {
                    mark.control = ArrowGeometry.defaultBend(from: mark.start, to: mark.end)
                }
            default:
                mark.end = constrained ? squared(from: mark.start, to: point) : point
            }
            draft = mark

        case .moving(let last):
            guard let index = selectedIndex else { return }
            annotations[index].move(by: CGSize(width: point.x - last.x, height: point.y - last.y))
            gesture = .moving(last: point)
            hasUnsavedChanges = true

        case .handle(let handle):
            guard let index = selectedIndex else { return }
            handle.drag(&annotations[index], to: point, constrained: constrained)
            hasUnsavedChanges = true

        case .cropping(let origin):
            cropRect = CGRect(origin: origin, size: .zero)
                .union(CGRect(origin: clamp(constrained ? squared(from: origin, to: point) : point), size: .zero))
                .intersection(CGRect(origin: .zero, size: imageSize))

        case .movingCrop(let last):
            guard let crop = cropRect else { return }
            var moved = crop.offsetBy(dx: point.x - last.x, dy: point.y - last.y)
            moved.origin.x = min(max(moved.minX, 0), imageSize.width - moved.width)
            moved.origin.y = min(max(moved.minY, 0), imageSize.height - moved.height)
            cropRect = moved
            gesture = .movingCrop(last: point)

        case .cropHandle(let handle):
            guard var box = cropBox else { return }
            handle.drag(&box, to: clamp(point), constrained: constrained)
            cropRect = box.rect.intersection(CGRect(origin: .zero, size: imageSize))

        case nil:
            break
        }
    }

    func pointerUp() {
        switch gesture {
        case .drawing:
            if let mark = draft {
                draft = nil
                if !mark.isNegligible {
                    pushUndo(gestureSnapshot, named: String(localized: "Add \(mark.tool.title)"))
                    annotations.append(mark)
                    select(mark.id)
                }
            }
        case .cropping:
            if let crop = cropRect, crop.width < 8 || crop.height < 8 {
                cropRect = gestureSnapshot?.cropRect
            } else {
                pushUndo(gestureSnapshot, named: String(localized: "Crop"))
            }
        case .movingCrop, .cropHandle:
            if let crop = cropRect, crop.width < 8 || crop.height < 8 {
                cropRect = gestureSnapshot?.cropRect
            } else {
                pushUndo(gestureSnapshot, named: String(localized: "Crop"))
            }
        case .moving:
            pushUndo(gestureSnapshot, named: String(localized: "Move"))
        case .handle:
            pushUndo(gestureSnapshot, named: String(localized: "Reshape"))
        case nil:
            break
        }
        gesture = nil
        gestureSnapshot = nil
    }

    var isDragging: Bool { gesture != nil }

    // MARK: Selection and editing

    func select(_ id: Annotation.ID?) {
        guard selectedID != id else { return }
        withAnimation(.response) { selectedID = id }
        lastStyleEdit = nil
    }

    func beginEditing(_ id: Annotation.ID) {
        select(id)
        editingTextID = id
        textEditSnapshot = snapshot
    }

    func updateText(_ text: String, for id: Annotation.ID) {
        guard let index = annotations.firstIndex(where: { $0.id == id }), annotations[index].text != text else { return }
        annotations[index].text = text
        hasUnsavedChanges = true
    }

    /// Ends text entry, removing the mark if nothing was typed.
    func finishTextEditing() {
        guard let id = editingTextID else { return }
        editingTextID = nil
        if let mark = annotations.first(where: { $0.id == id }), mark.isNegligible {
            withAnimation(.response) { annotations.removeAll { $0.id == id } }
            if selectedID == id { select(nil) }
        } else if let before = textEditSnapshot, before != snapshot {
            pushUndo(before, named: String(localized: "Typing"))
        }
        textEditSnapshot = nil
    }

    func deleteSelection() {
        guard let id = selectedID else { return }
        pushUndo(snapshot, named: String(localized: "Delete"))
        editingTextID = nil
        withAnimation(.response) {
            annotations.removeAll { $0.id == id }
        }
        select(nil)
    }

    func duplicateSelection() {
        guard var copy = selected else { return }
        pushUndo(snapshot, named: String(localized: "Duplicate"))
        copy.id = UUID()
        let offset = 16 * scale
        copy.move(by: CGSize(width: offset, height: offset))
        if copy.tool == .counter {
            copy.number = (annotations.filter { $0.tool == .counter }.map(\.number).max() ?? 0) + 1
        }
        withAnimation(.pop) { annotations.append(copy) }
        select(copy.id)
    }

    /// Covers each area with a redact mark in the redact tool's current style, as one undo step.
    func addRedactions(_ areas: [CGRect]) {
        let existing = annotations.filter { $0.tool == .redact }.map(\.rect.integral)
        let fresh = areas.filter { !existing.contains($0.integral) }
        guard !fresh.isEmpty else { return }
        pushUndo(snapshot, named: String(localized: "Hide Automatically"))
        let style = style(for: .redact)
        let marks = fresh.map { area in
            var mark = Annotation(tool: .redact, at: area.origin, style: style)
            mark.end = CGPoint(x: area.maxX, y: area.maxY)
            return mark
        }
        withAnimation(.pop) { annotations.append(contentsOf: marks) }
        select(nil)
    }

    func bringSelectionToFront() {
        guard let index = selectedIndex, index < annotations.count - 1 else { return }
        pushUndo(snapshot, named: String(localized: "Bring to Front"))
        let mark = annotations.remove(at: index)
        annotations.append(mark)
    }

    func sendSelectionToBack() {
        guard let index = selectedIndex, index > 0 else { return }
        pushUndo(snapshot, named: String(localized: "Send to Back"))
        let mark = annotations.remove(at: index)
        annotations.insert(mark, at: 0)
    }

    /// Moves the selection by whole points with the arrow keys.
    func nudgeSelection(dx: CGFloat, dy: CGFloat) {
        guard let index = selectedIndex else { return }
        coalescedUndo(for: annotations[index].id)
        annotations[index].move(by: CGSize(width: dx * scale, height: dy * scale))
    }

    func clearAll() {
        guard !annotations.isEmpty || cropRect != nil else { return }
        pushUndo(snapshot, named: String(localized: "Clear All"))
        withAnimation(.response) {
            annotations.removeAll()
            cropRect = nil
        }
        select(nil)
    }

    func resetCrop() {
        guard cropRect != nil else { return }
        pushUndo(snapshot, named: String(localized: "Reset Crop"))
        withAnimation(.response) { cropRect = nil }
    }

    /// Crops to a fixed aspect ratio, as large as fits and centered.
    func applyCropAspect(_ ratio: CGFloat) {
        let size = imageSize
        var width = size.width
        var height = width / ratio
        if height > size.height {
            height = size.height
            width = height * ratio
        }
        pushUndo(snapshot, named: String(localized: "Crop"))
        withAnimation(.response) {
            cropRect = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height).integral
        }
    }

    func undo() {
        finishTextEditing()
        guard undoManager.canUndo else { return }
        undoManager.undo()
        historyVersion += 1
    }

    func redo() {
        finishTextEditing()
        guard undoManager.canRedo else { return }
        undoManager.redo()
        historyVersion += 1
    }

    func markSaved(to url: URL) {
        fileURL = url
        hasUnsavedChanges = false
    }

    // MARK: Zoom

    func zoomIn(fitFactor: CGFloat) { setZoom(currentZoom(fitFactor: fitFactor) * 1.25) }
    func zoomOut(fitFactor: CGFloat) { setZoom(currentZoom(fitFactor: fitFactor) / 1.25) }

    func zoomToFit() {
        withAnimation(.panel) {
            zoom = nil
            pan = .zero
        }
    }

    func zoomToActualSize() { setZoom(1) }

    /// The zoom in effect, as a fraction of actual size.
    func currentZoom(fitFactor: CGFloat) -> CGFloat {
        zoom ?? fitFactor * scale
    }

    func setZoom(_ value: CGFloat) {
        withAnimation(.panel) { zoom = min(max(value, 0.1), 8) }
    }

    // MARK: Redaction

    /// The blurred or pixelated copy of the screenshot for the canvas. A strength that isn't
    /// ready yet is made in the background while the nearest finished one stands in, so
    /// dragging the Strength slider never stalls the window.
    func redactedImage(_ redaction: Redaction, strength: Double) -> CGImage? {
        guard redaction != .solid else { return nil }
        _ = redactionVersion
        let level = Self.level(for: strength)
        let key = Self.key(redaction, level)
        if let cached = redactionLayers[key] {
            touchRedactionLayer(key)
            return cached
        }
        prepareRedaction(redaction, levels: [level])
        let nearest = (0...10).sorted { abs($0 - level) < abs($1 - level) }
        return nearest.lazy.compactMap { self.redactionLayers[Self.key(redaction, $0)] }.first
    }

    /// The exact layer, made right away if needed. Used when exporting; a layer made here
    /// isn't kept, since the export is done with it as soon as it's drawn.
    func redactedImageNow(_ redaction: Redaction, strength: Double) -> CGImage? {
        guard redaction != .solid else { return nil }
        let level = Self.level(for: strength)
        if let cached = redactionLayers[Self.key(redaction, level)] { return cached }
        return Self.redacted(image, redaction: redaction, level: Double(level) / 10, scale: scale)
    }

    /// Makes the current strength and its two neighbours in the background, so nudging the
    /// Strength slider is instant. Further strengths are made when the slider reaches them.
    func prepareRedaction(_ redaction: Redaction, around strength: Double? = nil) {
        guard redaction != .solid else { return }
        let center = Self.level(for: strength ?? style(for: .redact).strength)
        prepareRedaction(redaction, levels: [center, center - 1, center + 1].filter { (0...10).contains($0) })
    }

    /// The most layers kept beyond the ones marks on the canvas are showing.
    private static let spareRedactionLayers = 3

    /// Lets go of every layer no mark is showing, when memory is short.
    func dropSpareRedactionLayers() {
        var inUse = Set(annotations.filter { $0.tool == .redact }.map { Self.key($0.style.redaction, Self.level(for: $0.style.strength)) })
        if tool == .redact {
            let toolStyle = style(for: .redact)
            inUse.insert(Self.key(toolStyle.redaction, Self.level(for: toolStyle.strength)))
        }
        for key in redactionLayers.keys where !inUse.contains(key) {
            redactionLayers[key] = nil
        }
        redactionLayerUse.removeAll { !inUse.contains($0) }
    }

    private func touchRedactionLayer(_ key: String) {
        guard redactionLayerUse.last != key else { return }
        redactionLayerUse.removeAll { $0 == key }
        redactionLayerUse.append(key)
    }

    /// Keeps `layer` and lets go of the least recently used ones beyond a few spares.
    /// Layers that marks on the canvas, or the redact tool itself, are using always stay;
    /// dropping them would only make the canvas ask for them again.
    private func keepRedactionLayer(_ layer: CGImage, for key: String) {
        redactionLayers[key] = layer
        touchRedactionLayer(key)
        var inUse = Set(annotations.filter { $0.tool == .redact }.map { Self.key($0.style.redaction, Self.level(for: $0.style.strength)) })
        let toolStyle = style(for: .redact)
        inUse.insert(Self.key(toolStyle.redaction, Self.level(for: toolStyle.strength)))
        var spares = redactionLayerUse.filter { !inUse.contains($0) }
        while spares.count > Self.spareRedactionLayers {
            let oldest = spares.removeFirst()
            redactionLayers[oldest] = nil
            redactionLayerUse.removeAll { $0 == oldest }
        }
    }

    private func prepareRedaction(_ redaction: Redaction, levels: [Int]) {
        let missing = levels.filter { redactionLayers[Self.key(redaction, $0)] == nil && !pendingRedactions.contains(Self.key(redaction, $0)) }
        guard !missing.isEmpty else { return }
        missing.forEach { pendingRedactions.insert(Self.key(redaction, $0)) }
        let image = image
        let scale = scale
        Task { [weak self] in
            for level in missing {
                let layer = await Self.redactedInBackground(image, redaction: redaction, level: Double(level) / 10, scale: scale)
                guard let self else { return }
                let key = Self.key(redaction, level)
                self.pendingRedactions.remove(key)
                if let layer {
                    self.keepRedactionLayer(layer, for: key)
                    self.redactionVersion += 1
                }
            }
        }
    }

    private static func level(for strength: Double) -> Int {
        Int((min(max(strength, 0), 1) * 10).rounded())
    }

    private static func key(_ redaction: Redaction, _ level: Int) -> String {
        "\(redaction.rawValue)-\(level)"
    }

    @concurrent
    private static func redactedInBackground(_ image: CGImage, redaction: Redaction, level: Double, scale: CGFloat) async -> CGImage? {
        redacted(image, redaction: redaction, level: level, scale: scale)
    }

    // MARK: Helpers

    private var snapshot: Snapshot { Snapshot(annotations: annotations, cropRect: cropRect) }
    private var selectedIndex: Int? { annotations.firstIndex { $0.id == selectedID } }

    private func applyStyle(_ newStyle: MarkStyle) {
        if let index = selectedIndex {
            let mark = annotations[index]
            guard mark.style != newStyle else { return }
            coalescedUndo(for: mark.id)
            annotations[index].style = newStyle
            if mark.style.route != newStyle.route, newStyle.route == .curved, annotations[index].control == nil {
                annotations[index].control = ArrowGeometry.defaultBend(from: mark.start, to: mark.end)
            }
            var remembered = newStyle
            if mark.tool == .highlighter, mark.style.lineWidth == newStyle.lineWidth {
                // A highlight snapped to text is as thick as that text. Recoloring it shouldn't
                // make every later stroke that thick.
                remembered.lineWidth = style(for: .highlighter).lineWidth
            }
            remember(remembered, for: mark.tool)
        } else {
            remember(newStyle, for: tool)
        }
    }

    /// Writes tool styles now instead of waiting, for when the window closes.
    func saveStylesNow() {
        styleSaveTask?.cancel()
        styleStore.save(toolStyles, scale: scale)
    }

    /// Every tool goes back to its original look. Marks already drawn keep theirs.
    func forgetToolStyles() {
        styleSaveTask?.cancel()
        toolStyles = [:]
    }

    private func remember(_ style: MarkStyle, for tool: EditorTool) {
        toolStyles[tool] = style
        if tool == .redact {
            prepareRedaction(style.redaction, around: style.strength)
        }
        styleSaveTask?.cancel()
        styleSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.styleStore.save(self.toolStyles, scale: self.scale)
        }
    }

    /// Records one undo step for a run of quick changes to the same mark, like dragging a slider.
    private func coalescedUndo(for id: Annotation.ID?) {
        let now = Date()
        if let last = lastStyleEdit, last.id == id, now.timeIntervalSince(last.date) < 1 {
            lastStyleEdit = (id, tool, now)
            hasUnsavedChanges = true
            return
        }
        pushUndo(snapshot, named: String(localized: "Change Style"))
        lastStyleEdit = (id, tool, now)
    }

    /// Records the state before a change as one undo step. Undoing it records the state it
    /// replaces, so redo always returns to exactly where you were.
    private func pushUndo(_ previous: Snapshot?, named name: String) {
        guard let previous, previous != snapshot else { return }
        registerUndo(restoring: previous, named: name)
        hasUnsavedChanges = true
    }

    private func registerUndo(restoring previous: Snapshot, named name: String) {
        undoManager.registerUndo(withTarget: self) { document in
            let current = document.snapshot
            document.restore(previous)
            document.registerUndo(restoring: current, named: name)
        }
        undoManager.setActionName(name)
        historyVersion += 1
    }

    private func restore(_ snapshot: Snapshot) {
        withAnimation(.response) {
            annotations = snapshot.annotations
            cropRect = snapshot.cropRect
        }
        if let id = selectedID, !annotations.contains(where: { $0.id == id }) {
            select(nil)
        }
        lastStyleEdit = nil
        hasUnsavedChanges = true
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), imageSize.width), y: min(max(point.y, 0), imageSize.height))
    }

    /// With Shift held, boxes become squares and circles.
    private func squared(from start: CGPoint, to point: CGPoint) -> CGPoint {
        let dx = point.x - start.x
        let dy = point.y - start.y
        let side = max(abs(dx), abs(dy))
        return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
    }

    nonisolated private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    nonisolated private static func redacted(_ image: CGImage, redaction: Redaction, level: Double, scale: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        let output: CIImage?
        switch redaction {
        case .blur:
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = input.clampedToExtent()
            // Even the weakest setting is strong enough that text underneath can't be read.
            filter.radius = Float((10 + 20 * level) * scale)
            output = filter.outputImage
        case .pixelate:
            let filter = CIFilter.pixellate()
            filter.inputImage = input.clampedToExtent()
            filter.scale = Float((10 + 18 * level) * scale)
            filter.center = .zero
            output = filter.outputImage
        case .solid:
            output = nil
        }
        guard let output else { return nil }
        let result = ciContext.createCGImage(output.cropped(to: input.extent), from: input.extent)
        if result == nil {
            Log.capture.error("Making the \(redaction.rawValue, privacy: .public) layer failed")
        }
        return result
    }
}

/// A grab point on a selected mark.
nonisolated enum MarkHandle: Hashable, Sendable {
    case start
    case end
    case bend
    /// Top-left, top-right, bottom-right, bottom-left.
    case corner(Int)
    /// Top, right, bottom, left.
    case edge(Int)

    /// The handles a mark offers, with where each one sits.
    static func handles(for mark: Annotation) -> [(MarkHandle, CGPoint)] {
        switch mark.tool {
        case .arrow:
            var handles: [(MarkHandle, CGPoint)] = [(.start, mark.start), (.end, mark.end)]
            if mark.style.route == .curved { handles.append((.bend, mark.resolvedControl)) }
            return handles
        case .highlighter where mark.isStraightStroke:
            return [(.start, mark.points[0]), (.end, mark.points[1])]
        case .shape, .redact:
            let r = mark.rect
            return [
                (.corner(0), CGPoint(x: r.minX, y: r.minY)), (.corner(1), CGPoint(x: r.maxX, y: r.minY)),
                (.corner(2), CGPoint(x: r.maxX, y: r.maxY)), (.corner(3), CGPoint(x: r.minX, y: r.maxY)),
                (.edge(0), CGPoint(x: r.midX, y: r.minY)), (.edge(1), CGPoint(x: r.maxX, y: r.midY)),
                (.edge(2), CGPoint(x: r.midX, y: r.maxY)), (.edge(3), CGPoint(x: r.minX, y: r.midY)),
            ]
        default:
            return []
        }
    }

    static func hit(at point: CGPoint, on mark: Annotation, tolerance: CGFloat) -> MarkHandle? {
        handles(for: mark)
            .map { ($0.0, hypot($0.1.x - point.x, $0.1.y - point.y)) }
            .filter { $0.1 <= tolerance }
            .min { $0.1 < $1.1 }?.0
    }

    var isCornerOrEdge: Bool {
        switch self {
        case .corner, .edge: true
        default: false
        }
    }

    func drag(_ mark: inout Annotation, to point: CGPoint, constrained: Bool) {
        switch self {
        case .start where mark.isStraightStroke:
            mark.points[0] = constrained ? Geometry.snapped(from: mark.points[1], to: point) : point
        case .end where mark.isStraightStroke:
            mark.points[1] = constrained ? Geometry.snapped(from: mark.points[0], to: point) : point
        case .start:
            mark.start = constrained ? Geometry.snapped(from: mark.end, to: point) : point
        case .end:
            mark.end = constrained ? Geometry.snapped(from: mark.start, to: point) : point
        case .bend:
            mark.control = point
        case .corner(let index):
            let r = mark.rect
            let opposite = [CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY)][index]
            var target = point
            if constrained {
                let dx = point.x - opposite.x
                let dy = point.y - opposite.y
                let side = max(abs(dx), abs(dy))
                target = CGPoint(x: opposite.x + (dx < 0 ? -side : side), y: opposite.y + (dy < 0 ? -side : side))
            }
            mark.start = opposite
            mark.end = target
        case .edge(let index):
            var r = mark.rect
            switch index {
            case 0: r = CGRect(x: r.minX, y: point.y, width: r.width, height: r.maxY - point.y)
            case 1: r.size.width = point.x - r.minX
            case 2: r.size.height = point.y - r.minY
            default: r = CGRect(x: point.x, y: r.minY, width: r.maxX - point.x, height: r.height)
            }
            r = r.standardized
            mark.start = r.origin
            mark.end = CGPoint(x: r.maxX, y: r.maxY)
        }
    }
}

nonisolated enum EditorCommand: Equatable, Sendable {
    case export
    case copyText
    case zoomIn
    case zoomOut
}

nonisolated struct EditorCommandRequest: Equatable, Sendable {
    let command: EditorCommand
    let id = UUID()
}
