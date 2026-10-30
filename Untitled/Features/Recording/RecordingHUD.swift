import AppKit
import SwiftUI

/// Floating controls shown while recording, plus an outline around the recorded area.
/// Untitled's own windows are left out of recordings, so neither shows up in the movie.
final class RecordingHUDController {
    var onStop: (() -> Void)?

    private var panel: NSPanel?
    private var frame: NSPanel?

    func show(recorder: ScreenRecorder, on screen: NSScreen?, framing area: CGRect?) {
        hide()
        guard let screen = screen ?? NSScreen.main else { return }

        let view = RecordingHUDView(recorder: recorder) { [weak self] in self?.onStop?() }
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let panel = FloatingPanel(contentRect: CGRect(origin: .zero, size: size))
        panel.contentView = hosting
        let visible = screen.visibleFrame
        panel.setFrameOrigin(CGPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 12))
        panel.orderFrontRegardless()
        self.panel = panel

        if let area {
            let outline = FloatingPanel(contentRect: area.insetBy(dx: -3, dy: -3))
            outline.ignoresMouseEvents = true
            outline.contentView = NSHostingView(rootView: RecordingOutline())
            outline.orderFrontRegardless()
            frame = outline
        }
    }

    func hide() {
        panel?.orderOut(nil)
        frame?.orderOut(nil)
        panel = nil
        frame = nil
    }
}

private struct RecordingHUDView: View {
    let recorder: ScreenRecorder
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "record.circle.fill")
                .foregroundStyle(.red)
                .symbolEffect(.pulse)
                .accessibilityHidden(true)
            elapsed
                .font(.body.monospacedDigit().weight(.medium))
            Button(action: onStop) {
                Label("Stop Recording", systemImage: "stop.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Stop recording")
            .disabled(recorder.state == .finishing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassCapsule()
        .padding(8)
    }

    @ViewBuilder
    private var elapsed: some View {
        if case .recording(let since) = recorder.state {
            TimelineView(.periodic(from: since, by: 1)) { context in
                Text(Duration.seconds(max(0, context.date.timeIntervalSince(since))).formatted(.time(pattern: .minuteSecond)))
            }
        } else {
            Text("Saving…")
        }
    }
}

/// A dashed outline just outside the recorded area.
private struct RecordingOutline: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .strokeBorder(Color.red.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
    }
}

/// A floating panel that never takes focus and appears on every Space.
private final class FloatingPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }
}

extension View {
    /// Liquid Glass on macOS 26 and later, a material capsule before that.
    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: .capsule)
        } else {
            background(.regularMaterial, in: .capsule)
        }
    }
}
