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
        panel.setHostedContent(hosting)
        let visible = screen.visibleFrame
        panel.setFrameOrigin(CGPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 12))
        panel.orderFrontRegardless()
        self.panel = panel

        if let area {
            let outline = FloatingPanel(contentRect: area.insetBy(dx: -3, dy: -3))
            outline.ignoresMouseEvents = true
            outline.setHostedContent(NSHostingView(rootView: RecordingOutline()))
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

    @State private var isShown = false

    var body: some View {
        GlassEffectContainer(spacing: Design.spacingS) {
            HStack(spacing: Design.spacingS) {
                HStack(spacing: Design.spacingS) {
                    Circle()
                        .fill(.red)
                        .frame(width: 9, height: 9)
                        .phaseAnimator([1.0, 0.35]) { dot, phase in
                            dot.opacity(phase)
                        } animation: { _ in .easeInOut(duration: 0.9) }
                        .accessibilityHidden(true)
                    elapsed
                        .font(.system(.body, design: .monospaced).weight(.medium))
                        .contentTransition(.numericText(countsDown: false))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .glassEffect(.regular, in: .capsule)

                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .glassEffect(.regular.tint(.red).interactive(), in: .circle)
                .help("Stop recording")
                .accessibilityLabel("Stop Recording")
                .disabled(recorder.state == .finishing)
            }
        }
        .scaleEffect(isShown ? 1 : 0.8)
        .opacity(isShown ? 1 : 0)
        .padding(10)
        .onAppear {
            withAnimation(.pop) { isShown = true }
        }
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
