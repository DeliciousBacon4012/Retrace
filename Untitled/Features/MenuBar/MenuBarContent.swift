import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The menu shown from the menu bar icon: stopping a recording, every screenshot, the
/// Record and Save Last menus, opening and pinning images, then the window and settings.
/// Each item shows its global shortcut.
struct MenuBarContent: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(SettingsStore.self) private var settings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let remaining = dependencies.recording.countdown {
            Button("Cancel Countdown — \(remaining)", systemImage: "xmark.circle") {
                dependencies.recording.cancelCountdown()
            }
            Divider()
        } else if dependencies.recording.isRecording {
            Button(stopTitle, systemImage: "stop.circle") {
                dependencies.recording.recorder.stop()
            }
            .disabled(dependencies.recording.recorder.state == .finishing)
            Divider()
        }

        Section {
            ForEach(QuickAction.all.filter(\.isScreenshot)) { action in
                QuickActionButton(action: action)
                    .menuShortcut(settings.shortcuts[action.id])
            }
        }

        Section {
            if !dependencies.recording.isRecording, dependencies.recording.countdown == nil {
                Menu("Record", systemImage: "record.circle") {
                    ForEach(QuickAction.recordings) { action in
                        QuickActionButton(action: action)
                            .menuShortcut(settings.shortcuts[action.id])
                    }
                }
            }
            Toggle("Replay Buffer", isOn: Binding(
                get: { settings.replayBufferEnabled },
                set: { dependencies.replay.setEnabled($0) }
            ))
            SaveLastMenu()
        }

        Section {
            Button("Open…", systemImage: "folder") {
                openImages()
            }
            ForEach(QuickAction.all.filter(\.opensClipboard)) { action in
                QuickActionButton(action: action)
                    .menuShortcut(settings.shortcuts[action.id])
            }
            Button("Pin to Screen…", systemImage: "pin") {
                dependencies.pins.pinFromFile()
            }
        }

        Section {
            Button("Show Recents", systemImage: "clock") {
                MainWindowRouter.shared.show(.recents, using: openWindow)
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

    /// "Stop Recording — 0:42", as of when the menu opened.
    private var stopTitle: String {
        switch dependencies.recording.recorder.state {
        case .recording(let since):
            let elapsed = Duration.seconds(max(0, Date.now.timeIntervalSince(since)).rounded(.down)).formatted(.time(pattern: .minuteSecond))
            return String(localized: "Stop Recording — \(elapsed)")
        case .finishing:
            return String(localized: "Saving Recording…")
        default:
            return String(localized: "Stop Recording")
        }
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

/// The menu bar icon. While recording it turns into a red record symbol, unless the time
/// has its own item. While the replay buffer runs, it shows a rewind symbol so it's never
/// on unnoticed.
struct MenuBarLabel: View {
    let recording: RecordingCoordinator
    let replay: ReplayCoordinator
    let settings: SettingsStore

    var body: some View {
        // With the time shown in its own menu bar item, this icon doesn't need to say it too.
        if recording.isRecording, !settings.showsRecordingTimeInMenuBar {
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
