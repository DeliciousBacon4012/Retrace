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
            if settings.textHistoryLimit > 0 {
                RecentTextMenu()
            } else {
                Button("Show Recents", systemImage: "clock") {
                    MainWindowRouter.shared.show(using: openWindow)
                }
            }
            ClipboardHistoryMenu()
        }

        Section {
            Button("Open retrace", systemImage: "macwindow") {
                MainWindowRouter.shared.show(using: openWindow)
            }
            Button("Settings…", systemImage: "gearshape") {
                MainWindowRouter.shared.showSettings(using: openWindow)
            }
            .keyboardShortcut(",")
        }

        Button("Quit retrace") {
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

/// Keeps retrace's logo in the menu bar; the adjacent status item shows recording time.
struct MenuBarLabel: View {
    let recording: RecordingCoordinator
    let settings: SettingsStore

    var body: some View {
        // Keep the native record symbol when someone has chosen to hide the separate timer.
        if recording.isRecording, !settings.showsRecordingTimeInMenuBar {
            Image(systemName: "record.circle.fill")
                .symbolRenderingMode(.multicolor)
                .accessibilityLabel("retrace, recording")
        } else {
            Image("retrace_menubar_template")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 18)
                .accessibilityLabel("retrace")
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
        .disabled(!action.isAvailable || (action.savesReplay && !dependencies.replay.buffer.isOn))
    }

    private var title: String {
        action.recordingMode != nil && dependencies.recording.isRecording
            ? String(localized: "Stop Recording")
            : action.title
    }
}

/// The last few things copied in any app. Choosing one copies it again.
private struct ClipboardHistoryMenu: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(SettingsStore.self) private var settings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var settings = settings
        Menu("Clipboard History", systemImage: "clipboard") {
            let entries = dependencies.clipboardHistory.entries.prefix(8)
            if entries.isEmpty {
                Text(settings.keepsClipboardHistory ? "What you copy appears here" : "Clipboard history is off")
            } else {
                ForEach(entries) { entry in
                    Button(title(for: entry), systemImage: entry.isImage ? "photo" : "text.alignleft") {
                        dependencies.clipboardHistory.copy(entry)
                    }
                }
            }
            Divider()
            Toggle("Keep Clipboard History", isOn: $settings.keepsClipboardHistory)
            Button("Show All") {
                MainWindowRouter.shared.show(libraryCategories: [.clipboard], using: openWindow)
            }
        }
    }

    private func title(for entry: ClipboardEntry) -> String {
        switch entry.content {
        case .text(let text):
            let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.count > 48 ? String(trimmed.prefix(47)) + "…" : trimmed
        case .image(_, let width, let height):
            return String(localized: "Image \(width) × \(height)")
        }
    }
}

/// The last few snippets Capture Text copied. Choosing one copies it again.
private struct RecentTextMenu: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Menu("Recent Text", systemImage: "text.quote") {
            let snippets = dependencies.textHistory.snippets.prefix(5)
            if snippets.isEmpty {
                Text("Text you capture appears here")
            } else {
                ForEach(snippets) { snippet in
                    Button(snippet.summary) {
                        dependencies.clipboard.copy(text: snippet.text)
                    }
                }
            }
            Divider()
            Button("Show All in Recents") {
                MainWindowRouter.shared.show(libraryCategories: [.capturedText], using: openWindow)
            }
        }
    }
}
