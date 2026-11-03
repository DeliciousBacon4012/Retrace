import AppKit

/// What the person picked in the selection overlay.
enum ScreenSelection {
    /// An area in AppKit screen coordinates, on one screen.
    case area(CGRect, NSScreen)
    case window(WindowCandidate)
}

/// Covers every screen with a transparent overlay and lets the person drag out an area
/// or click a window. Escape, or switching away, cancels.
final class SelectionOverlay {
    enum Mode {
        case area
        case window([WindowCandidate])
    }

    private var windows: [OverlayWindow] = []
    private var continuation: CheckedContinuation<ScreenSelection?, Never>?
    private var resignObserver: NSObjectProtocol?
    private weak var previousKeyWindow: NSWindow?

    /// Shows the overlay and waits for a selection. Returns `nil` if the person cancels.
    func select(_ mode: Mode) async -> ScreenSelection? {
        finish(with: nil)
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            present(mode)
        }
    }

    private func present(_ mode: Mode) {
        previousKeyWindow = NSApp.keyWindow
        for screen in NSScreen.screens {
            let view = OverlayView(mode: mode, screen: screen) { [weak self] selection in
                self?.finish(with: selection)
            }
            let window = OverlayWindow(screen: screen, contentView: view)
            windows.append(window)
            window.orderFrontRegardless()
        }

        let keyWindow = windows.first { $0.screen == NSScreen.underPointer } ?? windows.first
        keyWindow?.makeKey()
        if let view = keyWindow?.contentView {
            keyWindow?.makeFirstResponder(view)
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.finish(with: nil)
            }
        }
    }

    private func finish(with selection: ScreenSelection?) {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        resignObserver = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        // The overlay took keyboard focus without activating the app, so hand it back.
        if previousKeyWindow?.isVisible == true { previousKeyWindow?.makeKey() }
        previousKeyWindow = nil
        continuation?.resume(returning: selection)
        continuation = nil
    }
}

/// A borderless, transparent panel that covers one screen. It takes keyboard focus
/// without activating the app, so Untitled's other windows stay where they are.
private final class OverlayWindow: NSPanel {
    init(screen: NSScreen, contentView: NSView) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        setFrame(screen.frame, display: false)
        self.contentView = contentView
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
}

/// Draws the dimmed screen, the selection, and its size, and turns mouse input into a selection.
private final class OverlayView: NSView {
    private let mode: SelectionOverlay.Mode
    private let screen: NSScreen
    private let onFinish: (ScreenSelection?) -> Void

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var hoveredWindow: WindowCandidate?

    init(mode: SelectionOverlay.Mode, screen: NSScreen, onFinish: @escaping (ScreenSelection?) -> Void) {
        self.mode = mode
        self.screen = screen
        self.onFinish = onFinish
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self
        ))
        updateHoveredWindow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: Input

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onFinish(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        if case .window = mode {
            updateHoveredWindow()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard case .area = mode else { return }
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        dragCurrent = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard case .area = mode, dragStart != nil else { return }
        dragCurrent = clamped(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch mode {
        case .area:
            guard let rect = selectionRect, rect.width >= 2, rect.height >= 2 else {
                dragStart = nil
                dragCurrent = nil
                needsDisplay = true
                return
            }
            let global = rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
            onFinish(.area(global, screen))
        case .window:
            updateHoveredWindow()
            if let hoveredWindow {
                onFinish(.window(hoveredWindow))
            }
        }
    }

    private var selectionRect: CGRect? {
        guard let dragStart, let dragCurrent else { return nil }
        return CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragCurrent.x - dragStart.x),
            height: abs(dragCurrent.y - dragStart.y)
        ).integral
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), bounds.maxX), y: min(max(point.y, 0), bounds.maxY))
    }

    private func updateHoveredWindow() {
        guard case .window(let candidates) = mode else { return }
        let location = NSEvent.mouseLocation
        let hovered = candidates.first { $0.frame.contains(location) }
        if hovered?.id != hoveredWindow?.id {
            hoveredWindow = hovered
            needsDisplay = true
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        switch mode {
        case .area:
            drawAreaSelection()
        case .window:
            drawWindowHighlight()
        }
    }

    private func drawAreaSelection() {
        let dim = NSBezierPath(rect: bounds)
        if let rect = selectionRect {
            dim.appendRect(rect)
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.3).setFill()
        dim.fill()

        guard let rect = selectionRect else { return }
        let border = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        NSColor.white.withAlphaComponent(0.9).setStroke()
        border.stroke()

        let scale = screen.backingScaleFactor
        let label = "\(Int(rect.width * scale)) × \(Int(rect.height * scale))"
        drawLabel(label, below: rect)
    }

    private func drawWindowHighlight() {
        NSColor.black.withAlphaComponent(0.12).setFill()
        bounds.fill()

        guard let hoveredWindow else { return }
        let rect = hoveredWindow.frame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        guard rect.intersects(bounds) else { return }

        let shape = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
        shape.fill()
        shape.lineWidth = 2
        NSColor.controlAccentColor.setStroke()
        shape.stroke()
    }

    private func drawLabel(_ text: String, below rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        let padding = CGSize(width: 8, height: 4)
        var origin = CGPoint(x: rect.midX - size.width / 2 - padding.width, y: rect.minY - size.height - padding.height * 2 - 8)
        if origin.y < 4 {
            origin.y = rect.maxY + 8
        }
        origin.x = min(max(origin.x, 4), bounds.maxX - size.width - padding.width * 2 - 4)

        let background = CGRect(origin: origin, size: CGSize(width: size.width + padding.width * 2, height: size.height + padding.height * 2))
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: background, xRadius: 6, yRadius: 6).fill()
        string.draw(at: CGPoint(x: background.minX + padding.width, y: background.minY + padding.height))
    }
}
