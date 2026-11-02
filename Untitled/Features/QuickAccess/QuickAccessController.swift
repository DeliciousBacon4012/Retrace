import AppKit
import SwiftUI

/// Shows a floating thumbnail for each new capture, stacked in the corner chosen in Settings.
///
/// The whole stack lives in one window so its layout is a single calculation (see
/// `StackGeometry`): collapsed, older thumbnails peek out behind the newest; with the pointer
/// over it, the stack rises into evenly spaced floors. Drag a thumbnail into any app to drop
/// the file, or flick it toward the screen edge to put it away.
final class QuickAccessController {
    private let settings: SettingsStore
    private let clipboard: any ClipboardWriting
    private let model = QuickAccessStackModel()

    private var panel: QuickAccessPanel?
    private var screen: NSScreen?
    private var isPointerInside = false
    private var hoverTask: Task<Void, Never>?
    private var resizeTask: Task<Void, Never>?
    private var closeTasks: [UUID: Task<Void, Never>] = [:]
    /// When each thumbnail closes on its own, so hovering can pause and resume the countdown.
    private var deadlines: [UUID: Date] = [:]
    private var pausedRemaining: [UUID: TimeInterval] = [:]
    private var screenObserver: (any NSObjectProtocol)?

    /// Opens a capture in the editor; set once the editor exists.
    var onAnnotate: ((CapturedImage) -> Void)?
    /// Pins a capture to the screen.
    var onPin: ((CapturedImage) -> Void)?
    /// Saves a capture that wasn't saved yet and returns where it went.
    var onSave: ((CapturedImage) -> URL?)?

    init(settings: SettingsStore, clipboard: any ClipboardWriting) {
        self.settings = settings
        self.clipboard = clipboard
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenParametersChanged() }
        }
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var alwaysExpanded: Bool { settings.quickAccessLayout == .column }

    // MARK: Showing and closing

    func show(_ capture: CapturedImage) {
        if model.cards.isEmpty {
            screen = NSScreen.underPointer ?? NSScreen.main
        }
        applySettings()

        let card = QuickAccessStackModel.Card(id: capture.id, capture: capture, thumbnail: Self.thumbnail(of: capture, size: model.geometry.cardSize))
        let panel = panel ?? makePanel()
        // Grow first, away from the corner, so nothing on screen moves when the window does.
        resizePanel(count: model.cards.count + 1, expanded: model.isExpanded, immediately: true)
        panel.orderFrontRegardless()

        withAnimation(insertAnimation) {
            model.cards.insert(card, at: 0)
        }
        scheduleAutoClose(capture.id)

        let limit = min(settings.quickAccessMaxVisible, model.geometry.capacity(forHeight: screen?.visibleFrame.height ?? 900))
        while model.cards.count > limit, let oldest = model.cards.last {
            dismiss(oldest.id)
        }
    }

    func dismiss(_ id: UUID, animated: Bool = true) {
        guard model.cards.contains(where: { $0.id == id }) else { return }
        closeTasks.removeValue(forKey: id)?.cancel()
        deadlines[id] = nil
        pausedRemaining[id] = nil
        if model.hoveredID == id { model.hoveredID = nil }

        withAnimation(animated ? removeAnimation : nil) {
            model.cards.removeAll { $0.id == id }
            if model.cards.count < 2, !alwaysExpanded { model.isExpanded = false }
        }
        model.swipeOffsets[id] = nil

        if model.cards.isEmpty {
            isPointerInside = false
            hoverTask?.cancel()
            let panel = panel
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(0.3))
                guard let self, model.cards.isEmpty else { return }
                panel?.orderOut(nil)
            }
        } else {
            resizePanel(count: model.cards.count, expanded: model.isExpanded, immediately: false)
        }
    }

    private var insertAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.42 * model.speed, dampingFraction: 0.78)
    }

    private var removeAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.32 * model.speed, dampingFraction: 0.9)
    }

    // MARK: Actions

    private func card(_ id: UUID) -> QuickAccessStackModel.Card? {
        model.cards.first { $0.id == id }
    }

    private func copy(_ id: UUID) {
        guard let capture = card(id)?.capture else { return }
        if capture.isVideo, let url = capture.fileURL {
            clipboard.copyFile(at: url)
        } else {
            clipboard.copy(capture.nsImage)
        }
    }

    private func save(_ id: UUID) {
        guard let capture = card(id)?.capture else { return }
        if capture.fileURL == nil, onSave?(capture) == nil {
            return
        }
        dismiss(id)
    }

    /// Moves the saved file to the Trash, so it can be put back, and closes the thumbnail.
    private func delete(_ id: UUID) {
        guard let capture = card(id)?.capture else { return }
        if let url = capture.fileURL {
            NSWorkspace.shared.recycle([url]) { _, error in
                if let error {
                    Task { @MainActor in ErrorPresenter.present(error) }
                }
            }
        }
        dismiss(id)
    }

    private func pin(_ id: UUID) {
        guard let capture = card(id)?.capture else { return }
        onPin?(capture)
        dismiss(id)
    }

    private func open(_ id: UUID) {
        guard let capture = card(id)?.capture else { return }
        if capture.isVideo {
            if let url = capture.fileURL { NSWorkspace.shared.open(url) }
            return
        }
        dismiss(id)
        onAnnotate?(capture)
    }

    // MARK: Hover

    /// Rises into floors shortly after the pointer arrives, and settles back a moment after
    /// it leaves, so passing over the corner doesn't make the stack flicker.
    private func pointerInside(_ inside: Bool) {
        isPointerInside = inside
        hoverTask?.cancel()
        if inside {
            pauseAutoClose()
        } else {
            resumeAutoClose()
        }
        guard !alwaysExpanded, model.cards.count > 1 else { return }

        if inside, !model.isExpanded {
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(80))
                guard let self, !Task.isCancelled, isPointerInside else { return }
                resizePanel(count: model.cards.count, expanded: true, immediately: true)
                model.isExpanded = true
            }
        } else if !inside, model.isExpanded {
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard let self, !Task.isCancelled, !isPointerInside else { return }
                model.isExpanded = false
                resizePanel(count: model.cards.count, expanded: false, immediately: false)
            }
        }
    }

    // MARK: Closing on its own

    private func scheduleAutoClose(_ id: UUID, after seconds: TimeInterval? = nil) {
        let delay = seconds ?? TimeInterval(settings.overlayAutoCloseSeconds)
        guard delay > 0 else { return }
        closeTasks[id]?.cancel()
        deadlines[id] = Date().addingTimeInterval(delay)
        guard !isPointerInside else {
            pauseAutoClose()
            return
        }
        closeTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.dismiss(id)
        }
    }

    private func pauseAutoClose() {
        for (id, deadline) in deadlines {
            closeTasks.removeValue(forKey: id)?.cancel()
            pausedRemaining[id] = max(deadline.timeIntervalSinceNow, 0)
        }
        deadlines.removeAll()
    }

    /// Picks up where each countdown left off, with at least a moment to spare.
    private func resumeAutoClose() {
        let paused = pausedRemaining
        pausedRemaining.removeAll()
        for (id, remaining) in paused where card(id) != nil {
            scheduleAutoClose(id, after: max(remaining, 1.5))
        }
    }

    // MARK: Window

    private func applySettings() {
        model.corner = settings.overlayCorner
        model.speed = settings.overlaySpeed.factor
        let size = settings.quickAccessSize.cardSize
        if model.geometry.cardSize != size {
            model.geometry.cardSize = size
        }
        if alwaysExpanded {
            model.isExpanded = true
        }
    }

    private func makePanel() -> QuickAccessPanel {
        let actions = QuickAccessStackView.Actions(
            copy: { [weak self] in self?.copy($0) },
            save: { [weak self] in self?.save($0) },
            delete: { [weak self] in self?.delete($0) },
            pin: { [weak self] in self?.pin($0) },
            open: { [weak self] in self?.open($0) },
            close: { [weak self] in self?.dismiss($0) },
            hoverStack: { [weak self] in self?.pointerInside($0) }
        )
        let view = QuickAccessHostingView(rootView: QuickAccessStackView(model: model, actions: actions))
        view.model = model
        view.fileURL = { [weak self] id in self?.card(id)?.capture.fileURL }
        view.onSwipeBegan = { [weak self] id in
            self?.closeTasks.removeValue(forKey: id)?.cancel()
        }
        view.onSwipeAway = { [weak self] id in self?.dismiss(id, animated: false) }

        let panel = QuickAccessPanel(contentRect: .zero)
        panel.setHostedContent(view)
        self.panel = panel
        return panel
    }

    /// Resizes the window around the stack, anchored to its corner. Growing happens at once;
    /// shrinking waits for the thumbnails to finish moving, so none of them gets clipped.
    private func resizePanel(count: Int, expanded: Bool, immediately: Bool) {
        guard let panel, let screen else { return }
        let size = model.geometry.panelSize(count: max(count, 1), expanded: expanded)
        let area = screen.visibleFrame
        let frame = CGRect(
            x: model.corner.isLeft ? area.minX : area.maxX - size.width,
            y: model.corner.isBottom ? area.minY : area.maxY - size.height,
            width: size.width,
            height: size.height
        )
        resizeTask?.cancel()
        if immediately || frame.height >= panel.frame.height || panel.frame.width != frame.width {
            panel.setFrame(frame, display: true)
            return
        }
        resizeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.45 * (self?.model.speed ?? 1)))
            guard let self, !Task.isCancelled, model.isExpanded == expanded, model.cards.count == count else { return }
            panel.setFrame(frame, display: true)
        }
    }

    /// Keeps the stack on a screen that still exists, in the right place after display changes.
    private func screenParametersChanged() {
        guard panel != nil, !model.cards.isEmpty else { return }
        let id = screen?.displayID
        screen = NSScreen.screens.first { $0.displayID == id } ?? NSScreen.main
        resizePanel(count: model.cards.count, expanded: model.isExpanded, immediately: true)
    }

    /// A copy at twice the thumbnail's size, enough for Retina without holding the full capture twice.
    private static func thumbnail(of capture: CapturedImage, size: CGSize) -> NSImage {
        let image = capture.image
        let target = CGSize(width: size.width * 2, height: size.height * 2)
        let factor = max(target.width / CGFloat(image.width), target.height / CGFloat(image.height))
        guard factor < 1,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: Int((CGFloat(image.width) * factor).rounded()),
                  height: Int((CGFloat(image.height) * factor).rounded()),
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return capture.nsImage }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        guard let small = context.makeImage() else { return capture.nsImage }
        return NSImage(cgImage: small, size: capture.pointSize)
    }
}

/// A floating window that never takes focus away from the app you're working in.
private final class QuickAccessPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
}

/// Hosts the stack and turns drags on a thumbnail into one of two gestures: a flick toward the
/// screen edge moves that thumbnail with the pointer and throws it away with its momentum; any
/// other drag carries the file into another app. Clicks, hovers, and double-clicks go to SwiftUI.
final class QuickAccessHostingView: NSHostingView<QuickAccessStackView> {
    weak var model: QuickAccessStackModel?
    var fileURL: (UUID) -> URL? = { _ in nil }
    var onSwipeAway: (UUID) -> Void = { _ in }
    var onSwipeBegan: (UUID) -> Void = { _ in }

    private enum Mode {
        case idle
        case undecided(UUID)
        case swiping(UUID)
    }

    private var mode: Mode = .idle
    private var downLocation: CGPoint = .zero
    private var downEvent: NSEvent?
    private var samples: [(time: TimeInterval, x: CGFloat)] = []
    /// NSHostingView already acts as a drag source for SwiftUI, so file drags use their own.
    private let dragSource = ThumbnailDragSource()

    private var edge: CGFloat {
        model?.corner.isLeft == true ? -1 : 1
    }

    override func mouseDown(with event: NSEvent) {
        mode = .idle
        downLocation = NSEvent.mouseLocation
        downEvent = event
        samples = []
        if let model, let id = model.cardID(at: topLeftPoint(for: event), in: bounds.size) {
            mode = .undecided(id)
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        let location = NSEvent.mouseLocation
        let dx = location.x - downLocation.x
        let dy = location.y - downLocation.y

        switch mode {
        case .idle:
            super.mouseDragged(with: event)

        case .undecided(let id):
            guard hypot(dx, dy) > 5 else { return }
            cancelSwiftUIPress(with: event)
            if abs(dx) > abs(dy) * 1.2, dx * edge > 0 {
                mode = .swiping(id)
                onSwipeBegan(id)
                track(location.x)
            } else {
                mode = .idle
                startFileDrag(for: id, with: downEvent ?? event)
            }

        case .swiping(let id):
            track(location.x)
            // Toward the edge follows the pointer; away from it resists, like a rubber band.
            let pull = dx * edge > 0 ? dx : dx * 0.2
            model?.swipeOffsets[id] = pull
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard case .swiping(let id) = mode, let model else {
            if case .undecided = mode { super.mouseUp(with: event) }
            if case .idle = mode { super.mouseUp(with: event) }
            mode = .idle
            return
        }
        mode = .idle
        track(NSEvent.mouseLocation.x)

        let travelled = (model.swipeOffsets[id] ?? 0) * edge
        let velocity = currentVelocity() * edge
        let width = model.geometry.cardSize.width
        if travelled > width * 0.35 || velocity > 500 {
            throwAway(id, from: travelled, velocity: max(velocity, 900))
        } else {
            springBack(id)
        }
    }

    // MARK: Swipe physics

    private func topLeftPoint(for event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return isFlipped ? local : CGPoint(x: local.x, y: bounds.height - local.y)
    }

    private func track(_ x: CGFloat) {
        let now = ProcessInfo.processInfo.systemUptime
        samples.append((now, x))
        samples.removeAll { now - $0.time > 0.1 }
    }

    /// Points per second over the last tenth of a second.
    private func currentVelocity() -> CGFloat {
        guard let first = samples.first, let last = samples.last, last.time > first.time else { return 0 }
        return (last.x - first.x) / CGFloat(last.time - first.time)
    }

    /// Keeps the hand's momentum: the faster the flick, the shorter the flight. The window ends at
    /// the screen edge, so the thumbnail slides off the screen rather than fading in mid-air.
    private func throwAway(_ id: UUID, from travelled: CGFloat, velocity: CGFloat) {
        guard let model else { return }
        let target = model.geometry.cardSize.width + model.geometry.padding * 2 + 20
        let duration = min(max(Double((target - travelled) / velocity), 0.12), 0.4) * model.speed
        withAnimation(.timingCurve(0.15, 0.6, 0.35, 1, duration: duration)) {
            model.swipeOffsets[id] = target * edge
        } completion: { [weak self] in
            self?.onSwipeAway(id)
        }
    }

    private func springBack(_ id: UUID) {
        withAnimation(.spring(response: 0.35 * (model?.speed ?? 1), dampingFraction: 0.62)) {
            model?.swipeOffsets[id] = 0
        }
    }

    // MARK: File drag

    private func startFileDrag(for id: UUID, with event: NSEvent) {
        guard let card = model?.cards.first(where: { $0.id == id }) else { return }
        let writer: any NSPasteboardWriting
        if let url = fileURL(id) {
            writer = url as NSURL
        } else {
            writer = card.capture.nsImage
        }
        let item = NSDraggingItem(pasteboardWriter: writer)
        let size = model?.geometry.cardSize ?? CGSize(width: 200, height: 125)
        let imageSize = NSSize(width: size.width * 0.8, height: size.height * 0.8)
        let origin = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(
            NSRect(x: origin.x - imageSize.width / 2, y: origin.y - imageSize.height / 2, width: imageSize.width, height: imageSize.height),
            contents: card.thumbnail
        )
        beginDraggingSession(with: [item], event: event, source: dragSource)
    }

    /// Ends SwiftUI's press without a click, so a drag that starts on a button never fires it.
    private func cancelSwiftUIPress(with event: NSEvent) {
        guard let window,
              let release = NSEvent.mouseEvent(
                  with: .leftMouseUp,
                  location: CGPoint(x: -10_000, y: -10_000),
                  modifierFlags: event.modifierFlags,
                  timestamp: event.timestamp,
                  windowNumber: window.windowNumber,
                  context: nil,
                  eventNumber: event.eventNumber,
                  clickCount: 1,
                  pressure: 0
              )
        else { return }
        super.mouseUp(with: release)
    }
}

/// Offers a thumbnail's file as a copy to other apps.
private final class ThumbnailDragSource: NSObject, NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : .generic
    }
}
