import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The menu shown from the menu bar icon: every capture, then opening and pinning images,
/// then history and settings. Each item shows its global shortcut.
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

        Section {
            ForEach(QuickAction.all.filter(\.isScreenshot)) { action in
                QuickActionButton(action: action)
                    .menuShortcut(settings.shortcuts[action.id])
            }
        }

        Section {
            if !dependencies.recording.isRecording {
                ForEach(QuickAction.recordings) { action in
                    QuickActionButton(action: action)
                        .menuShortcut(settings.shortcuts[action.id])
                }
            }
            ForEach(QuickAction.all.filter(\.savesReplay)) { action in
                QuickActionButton(action: action)
                    .menuShortcut(settings.shortcuts[action.id])
            }
            Toggle("Replay Buffer", isOn: Binding(
                get: { settings.replayBufferEnabled },
                set: { dependencies.replay.setEnabled($0) }
            ))
        }

        Section {
            Button("Open…", systemImage: "folder") {
                openImages()
            }
            ForEach(QuickAction.all.filter(\.opensClipboard)) { action in
                QuickActionButton(action: action)
                    .menuShortcut(settings.shortcuts[action.id])
            }
            Button("Pin to the Screen…", systemImage: "pin") {
                dependencies.pins.pinFromFile()
            }
        }

        Section {
            Button("Capture History…", systemImage: "clock.arrow.circlepath") {
                MainWindowRouter.shared.show(.library, using: openWindow)
            }
            Button("Open Untitled", systemImage: "macwindow") {
                MainWindowRouter.shared.show(using: openWindow)
            }
            Button("Settings…", systemImage: "gearshape") {
                MainWindowRouter.shared.show(.general, using: openWindow)
            }
            .keyboardShortcut(",")
        }

        Button("Quit Untitled") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func openImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.directoryURL = settings.saveFolderURL
        NSApplication.shared.activate()
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { dependencies.editor.open(fileAt: $0) }
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

/// Runs a quick action: a screenshot, a recording, a replay clip, or the clipboard's image.
struct QuickActionButton: View {
    let action: QuickAction
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        Button(title, systemImage: action.symbolName) {
            dependencies.perform(action)
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
