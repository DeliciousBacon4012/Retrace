import AppKit
import SwiftUI

/// A field that records a global shortcut. Click it, then press the keys.
/// Escape cancels and Delete clears.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    /// Called when recording starts and stops, so live shortcuts can pause meanwhile.
    var onRecordingChange: (Bool) -> Void = { _ in }

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var rejected = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggleRecording) {
                Text(label)
                    .monospacedDigit()
                    .foregroundStyle(isRecording ? Color.accentColor : shortcut == nil ? .secondary : .primary)
                    .frame(minWidth: 110)
                    .contentTransition(.numericText())
            }
            .buttonStyle(.bordered)
            .modifier(Shake(trigger: rejected))
            .help(isRecording ? "Press a shortcut, or Escape to cancel" : "Click to record a shortcut")
            .accessibilityLabel(shortcut.map { Text("Shortcut \($0.displayString)") } ?? Text("No shortcut"))
            .accessibilityHint("Click, then press the keys to use")

            if shortcut != nil, !isRecording {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear shortcut")
                .accessibilityLabel("Clear shortcut")
            }
        }
        .animation(.snappy, value: isRecording)
        .onDisappear(perform: stopRecording)
    }

    private var label: String {
        if isRecording { return String(localized: "Type Shortcut…") }
        return shortcut?.displayString ?? String(localized: "Record Shortcut")
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        guard monitor == nil else { return }
        isRecording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        if isRecording {
            isRecording = false
            onRecordingChange(false)
        }
    }

    private func handle(_ event: NSEvent) {
        let plain = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        if plain, event.keyCode == 53 { // Escape
            stopRecording()
        } else if plain, event.keyCode == 51 || event.keyCode == 117 { // Delete, Forward Delete
            shortcut = nil
            stopRecording()
        } else if let recorded = Shortcut(event: event) {
            shortcut = recorded
            stopRecording()
        } else {
            rejected.toggle()
            NSSound.beep()
        }
    }
}

/// A short horizontal shake, like a rejected password field.
private struct Shake: ViewModifier {
    let trigger: Bool

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, offset in
            view.offset(x: offset)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(-6, duration: 0.06)
                SpringKeyframe(6, duration: 0.08)
                SpringKeyframe(-4, duration: 0.08)
                SpringKeyframe(0, duration: 0.1)
            }
        }
    }
}
