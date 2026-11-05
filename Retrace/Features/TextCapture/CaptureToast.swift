import AppKit
import SwiftUI

/// A short glass notice at the top of the screen, such as "Copied 4 lines".
///
/// It springs in and fades away after the time set for its kind, or stays until clicked.
/// Hovering pauses it and shows its actions underneath; leaving starts the clock again
/// with whatever time was left, but never less than a moment to move away.
final class CaptureToastController {
    struct Toast {
        var kind: ToastKind
        var symbolName: String
        var title: String
        var detail: String?
        var actions: [Action] = []
        /// Ignores the time set for its kind, for a toast that says work is under way.
        var staysUntilReplaced = false
    }

    struct Action: Identifiable {
        let id = UUID()
        var title: String
        var systemImage: String
        var perform: () -> Void
    }

    private let settings: SettingsStore
    private let permissions: any PermissionProviding
    private var panel: FloatingPanel?
    /// Identifies the toast on screen, so a fading one can't touch the next one's timer.
    private var current = UUID()
    private var dismissTask: Task<Void, Never>?
    /// Time left on the clock, or `nil` for a toast that stays until it's clicked.
    private var remaining: Duration?
    private var clockStarted: ContinuousClock.Instant?

    init(settings: SettingsStore, permissions: any PermissionProviding) {
        self.settings = settings
        self.permissions = permissions
    }

    /// Shows `toast`, replacing any toast already on screen. Returns `false` when toasts are
    /// turned off, so a caller with something important to say can say it another way.
    @discardableResult
    func show(_ toast: Toast, on screen: NSScreen? = NSScreen.underPointer ?? NSScreen.main) -> Bool {
        guard settings.showsToasts else { return false }
        hide(animated: false)
        guard let screen else { return false }

        let id = UUID()
        current = id
        let view = CaptureToastView(
            toast: toast,
            previewLines: toast.kind == .textCopied ? settings.toastPreviewLines : 1,
            alignment: settings.toastPosition == .topRight ? .trailing : .center,
            perform: { [weak self] action in
                // Close first: the action may show a toast of its own.
                if self?.current == id { self?.hide(animated: true) }
                action.perform()
            },
            dismiss: { [weak self] in
                guard self?.current == id else { return }
                self?.hide(animated: true)
            },
            hoverChanged: { [weak self] isHovering in
                guard self?.current == id else { return }
                if isHovering { self?.pauseClock() } else { self?.resumeClock() }
            }
        )
        // The panel is sized for the actions too, so hovering never resizes the window;
        // the space they take is transparent until then.
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let panel = FloatingPanel(contentRect: CGRect(origin: .zero, size: size))
        panel.setHostedContent(hosting)
        let visible = screen.visibleFrame
        let x = switch settings.toastPosition {
        case .topCenter: visible.midX - size.width / 2
        case .topRight: visible.maxX - size.width - 12
        }
        panel.setFrameOrigin(CGPoint(x: x, y: visible.maxY - size.height - 12))
        panel.orderFrontRegardless()
        self.panel = panel

        let seconds = settings.toastSeconds(for: toast.kind)
        if seconds > 0, !toast.staysUntilReplaced {
            startClock(.seconds(seconds))
        }
        return true
    }

    /// Says Screen Recording access is needed, with a button to the right page of System
    /// Settings. With toasts off, it shows an alert instead, since this can't go unsaid.
    func showScreenRecordingNeeded(then retry: String) {
        permissions.requestScreenRecordingAccess()
        let permissions = permissions
        let shown = show(.init(
            kind: .error,
            symbolName: "lock.shield",
            title: String(localized: "Screen Recording access needed"),
            detail: retry,
            actions: [Action(title: String(localized: "Open System Settings"), systemImage: "gear") {
                permissions.openScreenRecordingSettings()
            }]
        ))
        if !shown {
            ErrorPresenter.present(CaptureError.permissionDenied, recovery: String(localized: "Turn on Retrace in System Settings › Privacy & Security › Screen & System Audio Recording, then \(retry.lowercased())"))
        }
    }

    func hide(animated: Bool) {
        dismissTask?.cancel()
        dismissTask = nil
        remaining = nil
        clockStarted = nil
        guard let panel else { return }
        self.panel = nil
        guard animated else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }

    // MARK: Clock

    private func startClock(_ duration: Duration) {
        dismissTask?.cancel()
        remaining = duration
        clockStarted = .now
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.hide(animated: true)
        }
    }

    private func pauseClock() {
        guard let remaining, let clockStarted, dismissTask != nil else { return }
        dismissTask?.cancel()
        dismissTask = nil
        self.remaining = max(remaining - (ContinuousClock.now - clockStarted), .zero)
        self.clockStarted = nil
    }

    private func resumeClock() {
        guard let remaining, dismissTask == nil else { return }
        startClock(max(remaining, .seconds(1.5)))
    }
}

private struct CaptureToastView: View {
    let toast: CaptureToastController.Toast
    let previewLines: Int
    /// Keeps the notice against the screen edge when the actions are wider than it.
    let alignment: HorizontalAlignment
    let perform: (CaptureToastController.Action) -> Void
    let dismiss: () -> Void
    let hoverChanged: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false
    @State private var isHovering = false
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: Design.spacingS) {
            VStack(alignment: alignment, spacing: Design.spacingS) {
                notice
                if !toast.actions.isEmpty {
                    actions
                }
            }
        }
        .scaleEffect(isShown || reduceMotion ? 1 : 0.85, anchor: .top)
        .offset(y: isShown || reduceMotion ? 0 : -16)
        .opacity(isShown ? 1 : 0)
        .padding(10)
        .onHover { hovering in
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .response) { isHovering = hovering }
            hoverChanged(hovering)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .pop) { isShown = true }
        }
    }

    private var notice: some View {
        HStack(spacing: Design.spacingM) {
            Image(systemName: toast.symbolName)
                .font(.system(size: 17, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .symbolEffect(.bounce, value: isShown)
            VStack(alignment: .leading, spacing: 1) {
                Text(toast.title)
                    .font(.callout.weight(.semibold))
                if let detail = toast.detail {
                    Text(detail)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(previewLines)
                        .truncationMode(.tail)
                        .frame(maxWidth: 280, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: shape)
        .glassEffectID("notice", in: glass)
        .contentShape(.rect)
        .onTapGesture(perform: dismiss)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text("Dismiss"), dismiss)
        .accessibilityActions {
            ForEach(toast.actions) { action in
                Button(action.title) { perform(action) }
            }
        }
    }

    /// A capsule for one line, a rounded rectangle once a text preview wraps.
    private var shape: AnyShape {
        previewLines > 1 && toast.detail != nil ? AnyShape(RoundedRectangle(cornerRadius: Design.radiusL, style: .continuous)) : AnyShape(Capsule())
    }

    /// Flow out of the notice while the pointer is over the toast. Their room is always laid
    /// out, so the window never resizes.
    private var actions: some View {
        actionRow(isLive: false)
            .hidden()
            .overlay {
                if isHovering {
                    actionRow(isLive: true)
                }
            }
            .accessibilityHidden(!isHovering)
    }

    private func actionRow(isLive: Bool) -> some View {
        HStack(spacing: Design.spacingS) {
            ForEach(toast.actions) { action in
                Button(action.title, systemImage: action.systemImage) { perform(action) }
                    .buttonStyle(.glass)
                    .controlSize(.regular)
                    .glassEffectID(isLive ? action.id : nil, in: glass)
            }
        }
    }
}

extension [CaptureToastController.Action] {
    /// Open · Show in Finder · Copy, for a saved recording or replay.
    static func forMovie(at url: URL, clipboard: any ClipboardWriting) -> Self {
        [
            Element(title: String(localized: "Open"), systemImage: "play") { NSWorkspace.shared.open(url) },
            Element(title: String(localized: "Show in Finder"), systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            },
            Element(title: String(localized: "Copy"), systemImage: "doc.on.doc") { clipboard.copyFile(at: url) },
        ]
    }
}
