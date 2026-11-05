import AppKit
import Observation
import SwiftUI

/// Asks which display to record when more than one is connected.
///
/// Every display gets a panel. The one under the pointer glows with a soft border in the accent
/// color and shows a Record This Display button; the others dim a little. Click anywhere on a
/// display, or press Return, to record it. Arrow keys and Tab move between displays, and
/// Escape or switching apps cancels.
final class DisplayPicker {
    private var panels: [NSPanel] = []
    private var continuation: CheckedContinuation<CGDirectDisplayID?, Never>?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private weak var previousKeyWindow: NSWindow?
    private let model = DisplayPickerModel()

    /// True while the panels are up, waiting for a choice.
    var isPicking: Bool { continuation != nil }

    /// Shows the panels and waits. Returns `nil` if the person cancels.
    func pick() async -> NSScreen? {
        finish(with: nil)
        let displayID = await withCheckedContinuation { continuation in
            self.continuation = continuation
            present()
        }
        return NSScreen.screens.first { $0.displayID == displayID && displayID != nil }
    }

    func cancel() {
        finish(with: nil)
    }

    private func present() {
        previousKeyWindow = NSApp.keyWindow
        let screens = NSScreen.screens.filter { $0.displayID != nil }
        model.displays = screens.compactMap(\.displayID)
        model.hovered = NSScreen.underPointer?.displayID ?? model.displays.first

        for screen in screens {
            guard let displayID = screen.displayID else { continue }
            let view = DisplayPickerView(
                model: model,
                displayID: displayID,
                name: screen.localizedName,
                onPick: { [weak self] in self?.choose(displayID) },
                onCancel: { [weak self] in self?.finish(with: nil) }
            )
            let hosting = DisplayPickerHostingView(rootView: view) { [weak self] in
                self?.model.hover(displayID)
            }
            let panel = DisplayPickerPanel(screen: screen)
            panel.contentView = hosting
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        (panels.first { $0.screen == NSScreen.underPointer } ?? panels.first)?.makeKey()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isPicking else { return event }
            return self.handle(event) ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(with: nil) }
        }
    }

    /// Returns whether the key was used.
    private func handle(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // Escape
            finish(with: nil)
        case 36, 76, 49: // Return, Enter, Space
            if let hovered = model.hovered { choose(hovered) }
        case 124, 125: // Right, Down
            model.step(by: 1)
        case 123, 126: // Left, Up
            model.step(by: -1)
        case 48: // Tab, Shift-Tab
            model.step(by: event.modifierFlags.contains(.shift) ? -1 : 1)
        default:
            return false
        }
        return true
    }

    private func choose(_ displayID: CGDirectDisplayID) {
        Haptics.generic()
        finish(with: displayID)
    }

    private func finish(with displayID: CGDirectDisplayID?) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        if previousKeyWindow?.isVisible == true { previousKeyWindow?.makeKey() }
        previousKeyWindow = nil
        continuation?.resume(returning: displayID)
        continuation = nil
    }
}

@Observable
private final class DisplayPickerModel {
    var displays: [CGDirectDisplayID] = []
    var hovered: CGDirectDisplayID?

    func hover(_ displayID: CGDirectDisplayID) {
        guard hovered != displayID else { return }
        hovered = displayID
        Haptics.alignment()
    }

    func step(by offset: Int) {
        guard !displays.isEmpty else { return }
        let index = hovered.flatMap { displays.firstIndex(of: $0) } ?? 0
        hovered = displays[(index + offset + displays.count) % displays.count]
    }
}

/// A borderless panel over one whole display. It takes keys without activating Retrace, so
/// whatever is being recorded stays in front.
private final class DisplayPickerPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
}

/// Reports when the pointer enters its display, even while another app is in front, and
/// takes the first click instead of spending it on bringing the panel forward.
private final class DisplayPickerHostingView: NSHostingView<DisplayPickerView> {
    private let onEnter: () -> Void

    init(rootView: DisplayPickerView, onEnter: @escaping () -> Void) {
        self.onEnter = onEnter
        super.init(rootView: rootView)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    @available(*, unavailable)
    required init(rootView: DisplayPickerView) {
        fatalError("init(rootView:) is not used")
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) {
        onEnter()
        super.mouseEntered(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        onEnter()
        super.mouseMoved(with: event)
    }
}

private struct DisplayPickerView: View {
    let model: DisplayPickerModel
    let displayID: CGDirectDisplayID
    let name: String
    let onPick: () -> Void
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isHovered: Bool { model.hovered == displayID }

    var body: some View {
        ZStack {
            // The whole display is the target, as in the system's screenshot toolbar.
            Rectangle()
                .fill(.black.opacity(isHovered ? 0.001 : 0.28))
                .onTapGesture(perform: onPick)
                .accessibilityElement()
                .accessibilityLabel("Record \(name)")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onPick() }

            DisplayGlow()
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if isHovered {
                GlassEffectContainer(spacing: Design.spacingM) {
                    VStack(spacing: Design.spacingM) {
                        Button(action: onPick) {
                            Label("Record This Display", systemImage: "record.circle")
                                .font(.title3.weight(.semibold))
                                .padding(.horizontal, Design.spacingS)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.extraLarge)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityLabel("Record \(name)")

                        HStack(spacing: Design.spacingS) {
                            Text(name).fontWeight(.medium)
                            Text("·").foregroundStyle(.secondary)
                            Text("Click a display to record it, or press Esc to cancel")
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                    }
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .response, value: isHovered)
        .onExitCommand(perform: onCancel)
        .contextMenu {
            Button("Record \(name)", action: onPick)
            Button("Cancel", action: onCancel)
        }
    }
}

/// A soft border in shades of the accent color around the inside edge of the display: a crisp
/// line with a wide, blurred glow behind it.
private struct DisplayGlow: View {
    var body: some View {
        let accent = Color.accentColor
        let gradient = AngularGradient(
            colors: [
                accent,
                accent.mix(with: .white, by: 0.45),
                accent.mix(with: .purple, by: 0.35),
                accent.mix(with: .cyan, by: 0.3),
                accent,
            ],
            center: .center
        )
        ZStack {
            Rectangle()
                .strokeBorder(gradient, lineWidth: 28)
                .blur(radius: 26)
                .opacity(0.75)
            Rectangle()
                .strokeBorder(gradient, lineWidth: 4)
                .blur(radius: 1.5)
        }
    }
}
