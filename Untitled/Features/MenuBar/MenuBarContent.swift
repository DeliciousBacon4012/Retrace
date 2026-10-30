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
struct MenuBarLabel: View {
    let recording: RecordingCoordinator

    var body: some View {
        Image(systemName: recording.isRecording ? "record.circle.fill" : "camera.aperture")
            .symbolRenderingMode(recording.isRecording ? .multicolor : .monochrome)
            .accessibilityLabel(recording.isRecording ? "Untitled, recording" : "Untitled")
    }
}

/// Runs a quick action: a screenshot, or starting or stopping a recording.
struct QuickActionButton: View {
    let action: QuickAction
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        Button(title, systemImage: action.symbolName) {
            if let mode = action.captureMode {
                Task { await dependencies.capture.capture(mode) }
            } else if let mode = action.recordingMode {
                Task { await dependencies.recording.toggle(mode) }
            }
        }
        .labelStyle(.titleAndIcon)
        .disabled(!action.isAvailable)
    }

    private var title: String {
        action.recordingMode != nil && dependencies.recording.isRecording
            ? String(localized: "Stop Recording")
            : action.title
    }
}
