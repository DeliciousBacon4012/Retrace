import AppKit
import SwiftUI

/// The menu shown from the menu bar icon.
struct MenuBarContent: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(SettingsStore.self) private var settings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if dependencies.recording.isRecording {
            Button("Stop Recording", systemImage: "stop.circle") {
                dependencies.recording.recorder.stop()
            }
            Divider()
        }

        ForEach(QuickAction.all) { action in
            QuickActionButton(action: action)
                .menuShortcut(settings.shortcuts[action.id])
        }

        Toggle("Replay Buffer", isOn: Binding(
            get: { settings.replayBufferEnabled },
            set: { dependencies.replay.setEnabled($0) }
        ))

        Divider()

        Button("Open Untitled") {
            openWindow(id: WindowID.main)
            NSApplication.shared.activate()
        }

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit Untitled") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

/// The menu bar icon, which turns into a red record symbol while recording.
/// While the replay buffer runs, it shows a rewind symbol so it's never on unnoticed.
struct MenuBarLabel: View {
    let recording: RecordingCoordinator
    let replay: ReplayCoordinator

    var body: some View {
        if recording.isRecording {
            Image(systemName: "record.circle.fill")
                .symbolRenderingMode(.multicolor)
                .accessibilityLabel("Untitled, recording")
        } else if replay.buffer.isOn {
            Image(systemName: "gobackward")
                .accessibilityLabel("Untitled, replay buffer on")
        } else {
            Image(systemName: "camera.aperture")
                .accessibilityLabel("Untitled")
        }
    }
}

/// Runs a quick action: a screenshot, or starting or stopping a recording.
struct QuickActionButton: View {
    let action: QuickAction
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        Button(title, systemImage: action.symbolName) {
            if action.captureMode != nil || action.capturesText {
                Task { await dependencies.capture.run(action) }
            } else if let mode = action.recordingMode {
                Task { await dependencies.recording.toggle(mode) }
            } else if action.savesReplay {
                Task { await dependencies.replay.saveClip() }
            }
        }
        .labelStyle(.titleAndIcon)
        .disabled(!action.isAvailable || (action.savesReplay && !dependencies.replay.buffer.isOn))
    }

    private var title: String {
        action.recordingMode != nil && dependencies.recording.isRecording
            ? String(localized: "Stop Recording")
            : action.title
    }
}
