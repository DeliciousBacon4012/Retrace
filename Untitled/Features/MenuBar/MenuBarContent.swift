import AppKit
import SwiftUI

/// The menu shown from the menu bar icon.
struct MenuBarContent: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(SettingsStore.self) private var settings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ForEach(QuickAction.all) { action in
            if let mode = action.captureMode {
                Button(action.title, systemImage: action.symbolName) {
                    Task { await dependencies.capture.capture(mode) }
                }
                .menuShortcut(settings.shortcuts[action.id])
            } else {
                Button(action.title, systemImage: action.symbolName) {}
                    .disabled(true)
            }
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
