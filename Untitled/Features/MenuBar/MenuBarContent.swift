import AppKit
import SwiftUI

/// The menu shown from the menu bar icon.
struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ForEach(QuickAction.all) { action in
            Button(action.title, systemImage: action.symbolName) {}
                .disabled(true)
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
