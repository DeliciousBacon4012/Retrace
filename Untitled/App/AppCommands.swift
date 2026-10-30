import SwiftUI

/// Menu bar commands for the main window.
struct AppCommands: Commands {
    let capture: CaptureCoordinator
    let settings: SettingsStore

    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.selectedTab) private var selectedTab

    var body: some Commands {
        CommandMenu("Capture") {
            ForEach(QuickAction.all) { action in
                if let mode = action.captureMode {
                    Button(action.title, systemImage: action.symbolName) {
                        Task { await capture.capture(mode) }
                    }
                    .labelStyle(.titleAndIcon)
                    .menuShortcut(settings.shortcuts[action.id])
                } else {
                    Button(action.title, systemImage: action.symbolName) {}
                        .labelStyle(.titleAndIcon)
                        .disabled(true)
                }
            }
        }

        CommandGroup(before: .toolbar) {
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) {
                    selectedTab?.wrappedValue = tab
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .disabled(selectedTab == nil)
            }
            Divider()
        }

        CommandGroup(replacing: .help) {
            Button("Feature Roadmap") {
                openWindow(id: WindowID.roadmap)
            }
            if let url = URL(string: "https://github.com/DeliciousBacon4012/untitled-mac") {
                Link("Untitled on GitHub", destination: url)
            }
        }
    }
}
