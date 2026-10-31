import AppKit
import Observation
import QuartzCore
import SwiftUI

/// Which Quick Access thumbnail is in front: the one under the pointer, or else the newest.
@Observable
final class QuickAccessStack {
    fileprivate(set) var order: [UUID] = []
    var hoveredID: UUID?

    var focusedID: UUID? { hoveredID ?? order.last }
}

/// Shows a floating thumbnail for each new capture, stacked in the corner chosen in Settings.
///
/// The newest thumbnail sits nearest the corner and is a little larger; older ones step back,
/// slightly smaller, softer, and greyer, until the pointer moves over them. Drag a thumbnail
/// into any app to drop the file, or flick it toward the screen edge to put it away.
final class QuickAccessController {
    private struct Entry {
        let capture: CapturedImage
        let panel: NSPanel
        let view: ThumbnailHostingView
        var autoClose: Task<Void, Never>?
    }

    /// At most this many thumbnails are shown; older ones close first.
    private let maximumVisible = 5
    private let margin: CGFloat = 16
    /// How much of each thumbnail's height the next one up starts at, so the stack reads as one.
    private let stackStep: CGFloat = 0.9

    private let settings: SettingsStore
    private let clipboard: any ClipboardWriting
    private let stack = QuickAccessStack()
    private var entries: [Entry] = []

    /// Opens a capture in the editor; set once the editor exists.
    var onAnnotate: ((CapturedImage) -> Void)?
    /// Pins a capture to the screen.
    var onPin: ((CapturedImage) -> Void)?
    /// Saves a capture that wasn't saved yet and returns where it went.
    var onSave: ((CapturedImage) -> URL?)?

    init(settings: SettingsStore, clipboard: any ClipboardWriting) {
        self.settings = settings
        self.clipboard = clipboard
    }

    private var speed: Double { settings.overlaySpeed.factor }

    private var edgeDirection: CGFloat {
        switch settings.overlayCorner {
        case .bottomLeft, .topLeft: -1
        case .bottomRight, .topRight: 1
        }
    }

    func show(_ capture: CapturedImage) {
        let id = capture.id
        let actions = QuickAccessThumbnail.Actions(
            copy: { [weak self] in
                if capture.isVideo, let url = self?.entry(id)?.capture.fileURL {
                    self?.clipboard.copyFile(at: url)
                } else {
                    self?.clipboard.copy(capture.nsImage)
                }
            },
            save: { [weak self] in self?.save(id) },
            delete: { [weak self] in self?.delete(id) },
            pin: { [weak self] in
                guard let self, let entry = entry(id) else { return }
                onPin?(entry.capture)
                dismiss(id)
            },
            open: { [weak self] in
                guard let self, let entry = entry(id), !entry.capture.isVideo else {
                    if let url = self?.entry(id)?.capture.fileURL { NSWorkspace.shared.open(url) }
                    return
                }
                dismiss(id)
                onAnnotate?(entry.capture)
            },
            close: { [weak self] in self?.dismiss(id) },
            hover: { [weak self] hovering in self?.hoverChanged(id, hovering: hovering) }
        )
        let thumbnail = QuickAccessThumbnail(
            capture: capture,
            stack: stack,
            edge: edgeDirection,
            alignment: settings.overlayCorner,
            speed: speed,
            actions: actions
        )
        let view = ThumbnailHostingView(rootView: thumbnail)
        view.setFrameSize(view.fittingSize)
        view.fileURL = { [weak self] in self?.entry(id)?.capture.fileURL }
        view.dragImage = capture.nsImage
        view.edgeDirection = edgeDirection
        view.speed = speed
        view.onSwipeAway = { [weak self] in self?.dismiss(id, animated: false) }
        view.onSwipeBegan = { [weak self] in self?.entry(id)?.autoClose?.cancel() }

        let panel = ThumbnailPanel(contentRect: CGRect(origin: .zero, size: view.fittingSize))
        panel.contentView = view

        var entry = Entry(capture: capture, panel: panel, view: view)
        entry.autoClose = scheduleAutoClose(id)
        entries.append(entry)
        stack.order = entries.map(\.capture.id)

        while entries.count > maximumVisible, let oldest = entries.first {
            dismiss(oldest.capture.id)
        }
        layout(placingImmediately: panel)
        panel.orderFrontRegardless()
    }

    func dismiss(_ id: UUID, animated: Bool = true) {
        guard let index = entries.firstIndex(where: { $0.capture.id == id }) else { return }
        let entry = entries.remove(at: index)
        entry.autoClose?.cancel()
        stack.order = entries.map(\.capture.id)
        if stack.hoveredID == id { stack.hoveredID = nil }

        let panel = entry.panel
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22 * speed
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
                var frame = panel.frame
                frame.origin.x += edgeDirection * 24
                panel.animator().setFrame(frame, display: false)
            } completionHandler: {
                MainActor.assumeIsolated { panel.orderOut(nil) }
            }
        } else {
            panel.orderOut(nil)
        }
        layout(placingImmediately: nil)
    }

    // MARK: Actions

    private func entry(_ id: UUID) -> Entry? {
        entries.first { $0.capture.id == id }
    }

    private func save(_ id: UUID) {
        guard let entry = entry(id) else { return }
        if entry.capture.fileURL == nil, onSave?(entry.capture) == nil {
            return
        }
        dismiss(id)
    }

    /// Deletes the saved file (to the Trash, so it can be put back) and closes the thumbnail.
    private func delete(_ id: UUID) {
        guard let entry = entry(id) else { return }
        if let url = entry.capture.fileURL {
            NSWorkspace.shared.recycle([url]) { _, error in
                if let error {
                    Task { @MainActor in ErrorPresenter.present(error) }
                }
            }
        }
        dismiss(id)
    }

    private func hoverChanged(_ id: UUID, hovering: Bool) {
        if hovering {
            stack.hoveredID = id
            entry(id)?.panel.orderFrontRegardless()
            entry(id)?.autoClose?.cancel()
        } else if stack.hoveredID == id {
            stack.hoveredID = nil
            if let index = entries.firstIndex(where: { $0.capture.id == id }) {
                entries[index].autoClose = scheduleAutoClose(id)
            }
        }
    }

    private func scheduleAutoClose(_ id: UUID) -> Task<Void, Never>? {
        let seconds = settings.overlayAutoCloseSeconds
        guard seconds > 0 else { return nil }
        return Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss(id)
        }
    }

    // MARK: Layout

    /// Stacks the panels away from the chosen corner, newest nearest the corner.
    /// Panels already on screen glide to their new places; a new one appears in place.
    private func layout(placingImmediately newPanel: NSPanel?) {
        guard let screen = NSScreen.underPointer ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        let corner = settings.overlayCorner
        var offset: CGFloat = 0

        for entry in entries.reversed() {
            let size = entry.panel.frame.size
            let x: CGFloat = switch corner {
            case .bottomLeft, .topLeft: area.minX + margin
            case .bottomRight, .topRight: area.maxX - margin - size.width
            }
            let y: CGFloat = switch corner {
            case .bottomLeft, .bottomRight: area.minY + margin + offset
            case .topLeft, .topRight: area.maxY - margin - size.height - offset
            }
            let origin = CGPoint(x: x, y: y)
            offset += (size.height - ThumbnailMetrics.shadowPadding * 2) * stackStep

            guard !entry.view.isSwiping else { continue }
            if entry.panel === newPanel {
                entry.panel.setFrameOrigin(origin)
            } else if entry.panel.frame.origin != origin {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.42 * speed
                    // Settles like a spring: fast start, a whisker of overshoot, soft landing.
                    context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.12, 0.36, 1)
                    entry.panel.animator().setFrameOrigin(origin)
                }
            }
        }
    }
}

/// A floating panel that never takes focus away from the app you're working in.
private final class ThumbnailPanel: NSPanel {
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

/// Hosts a thumbnail and turns drags into one of two gestures: a flick toward the screen edge
/// moves the thumbnail with the pointer and throws it away with its momentum; any other drag
/// carries the file into another app. Clicks, hovers, and double-clicks go to SwiftUI.
final class ThumbnailHostingView: NSHostingView<QuickAccessThumbnail> {
    var fileURL: () -> URL? = { nil }
    var dragImage: NSImage?
    /// -1 when the thumbnails sit on the left edge, 1 on the right.
    var edgeDirection: CGFloat = -1
    var speed: Double = 1
    var onSwipeAway: () -> Void = {}
    var onSwipeBegan: () -> Void = {}

    private enum Mode {
        case undecided
        case swiping(startOrigin: CGPoint)
        case done
    }

    private var mode: Mode = .done
    private var downLocation: CGPoint = .zero
    private var downEvent: NSEvent?
    private var samples: [(time: TimeInterval, x: CGFloat)] = []

    private(set) var isSwiping = false

    override func mouseDown(with event: NSEvent) {
        mode = .undecided
        downLocation = NSEvent.mouseLocation
        downEvent = event
        samples = []
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        let location = NSEvent.mouseLocation
        let dx = location.x - downLocation.x
        let dy = location.y - downLocation.y

        switch mode {
        case .undecided:
            guard hypot(dx, dy) > 5, let window else { return }
            cancelSwiftUIPress(with: event)
            if abs(dx) > abs(dy) * 1.2, dx * edgeDirection > 0 {
                mode = .swiping(startOrigin: window.frame.origin)
                isSwiping = true
                onSwipeBegan()
                track(location.x)
            } else {
                mode = .done
                startFileDrag(with: downEvent ?? event)
            }

        case .swiping(let start):
            guard let window else { return }
            track(location.x)
            // Toward the edge follows the pointer; away from it resists, like a rubber band.
            let pull = dx * edgeDirection > 0 ? dx : dx * 0.2
            window.setFrameOrigin(CGPoint(x: start.x + pull, y: start.y))

        case .done:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard case .swiping(let start) = mode, let window else {
            if case .undecided = mode { super.mouseUp(with: event) }
            mode = .done
            return
        }
        mode = .done
        track(NSEvent.mouseLocation.x)

        let travelled = (window.frame.origin.x - start.x) * edgeDirection
        let velocity = currentVelocity() * edgeDirection
        let width = window.frame.width
        if travelled > width * 0.35 || velocity > 500 {
            throwAway(window: window, velocity: max(velocity, 900))
        } else {
            springBack(window: window, to: start)
        }
    }

    // MARK: Swipe physics

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

    private func throwAway(window: NSWindow, velocity: CGFloat) {
        guard let screen = window.screen ?? NSScreen.main else {
            onSwipeAway()
            return
        }
        var frame = window.frame
        let target = edgeDirection < 0 ? screen.frame.minX - frame.width - 20 : screen.frame.maxX + 20
        let distance = abs(target - frame.origin.x)
        frame.origin.x = target
        NSAnimationContext.runAnimationGroup { context in
            // Keep the hand's momentum: the faster the flick, the shorter the flight.
            context.duration = min(max(Double(distance / velocity), 0.12), 0.4) * speed
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.15, 0.6, 0.35, 1)
            window.animator().setFrame(frame, display: false)
            window.animator().alphaValue = 0.4
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.isSwiping = false
                self?.onSwipeAway()
            }
        }
    }

    private func springBack(window: NSWindow, to origin: CGPoint) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.45 * speed
            // Overshoots a touch past home, then settles, like a released spring.
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 1.45, 0.55, 1)
            window.animator().setFrameOrigin(origin)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.isSwiping = false }
        }
    }

    // MARK: File drag

    private func startFileDrag(with event: NSEvent) {
        let writer: any NSPasteboardWriting
        if let url = fileURL() {
            writer = url as NSURL
        } else if let dragImage {
            writer = dragImage
        } else {
            return
        }
        let item = NSDraggingItem(pasteboardWriter: writer)
        let imageSize = NSSize(width: min(bounds.width * 0.7, 180), height: min(bounds.height * 0.7, 120))
        let origin = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(
            NSRect(x: origin.x - imageSize.width / 2, y: origin.y - imageSize.height / 2, width: imageSize.width, height: imageSize.height),
            contents: dragImage
        )
        beginDraggingSession(with: [item], event: event, source: dragSource)
    }

    /// NSHostingView already acts as a drag source for SwiftUI, so file drags use their own.
    private let dragSource = ThumbnailDragSource()

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
