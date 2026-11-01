import AppKit
import SwiftUI

/// A short glass notice at the top of the screen, such as "Copied 4 lines",
/// with an optional button. It springs in and fades away after the time set for its kind,
/// or stays until it's clicked.
final class CaptureToastController {
    struct Toast {
        var kind: ToastKind
        var symbolName: String
        var title: String
        var detail: String?
        var actionTitle: String?
        var action: (() -> Void)?
    }

    private let settings: SettingsStore
    private var panel: FloatingPanel?
    private var dismissTask: Task<Void, Never>?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func show(_ toast: Toast, on screen: NSScreen? = NSScreen.underPointer ?? NSScreen.main) {
        guard settings.showsToasts else { return }
        hide(animated: false)
        guard let screen else { return }

        let view = CaptureToastView(toast: toast) { [weak self] in
            toast.action?()
            self?.hide(animated: true)
        } dismiss: { [weak self] in
            self?.hide(animated: true)
        }
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let panel = FloatingPanel(contentRect: CGRect(origin: .zero, size: size))
        panel.contentView = hosting
        let visible = screen.visibleFrame
        let x = switch settings.toastPosition {
        case .topCenter: visible.midX - size.width / 2
        case .topRight: visible.maxX - size.width - 12
        }
        panel.setFrameOrigin(CGPoint(x: x, y: visible.maxY - size.height - 12))
        panel.orderFrontRegardless()
        self.panel = panel

        let seconds = settings.toastSeconds(for: toast.kind)
        guard seconds > 0 else { return }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.hide(animated: true)
        }
    }

    func hide(animated: Bool) {
        dismissTask?.cancel()
        dismissTask = nil
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
}

private struct CaptureToastView: View {
    let toast: CaptureToastController.Toast
    let perform: () -> Void
    let dismiss: () -> Void

    @State private var isShown = false

    var body: some View {
        GlassEffectContainer(spacing: Design.spacingS) {
            HStack(spacing: Design.spacingS) {
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
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 280, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .contentShape(.capsule)
                .onTapGesture(perform: dismiss)
                .accessibilityElement(children: .combine)
                .accessibilityAction(named: Text("Dismiss"), dismiss)

                if let actionTitle = toast.actionTitle {
                    Button(actionTitle, action: perform)
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                }
            }
        }
        .scaleEffect(isShown ? 1 : 0.85, anchor: .top)
        .offset(y: isShown ? 0 : -16)
        .opacity(isShown ? 1 : 0)
        .padding(10)
        .onAppear {
            withAnimation(.pop) { isShown = true }
        }
    }
}
