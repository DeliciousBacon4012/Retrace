import SwiftUI
import UniformTypeIdentifiers

/// Menu bar commands for the main window.
struct AppCommands: Commands {
    let dependencies: AppDependencies

    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.selectedTab) private var selectedTab

    var body: some Commands {
        // Settings live in the main window's sidebar, so ⌘, opens it on General.
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                MainWindowRouter.shared.show(.general, using: openWindow)
            }
            .keyboardShortcut(",")
        }

        CommandGroup(after: .newItem) {
            Button("Open…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.image]
                panel.allowsMultipleSelection = true
                panel.directoryURL = dependencies.settings.saveFolderURL
                guard panel.runModal() == .OK else { return }
                panel.urls.forEach { dependencies.editor.open(fileAt: $0) }
            }
            .keyboardShortcut("o")
            Button("Pin to the Screen…") {
                dependencies.pins.pinFromFile()
            }
        }

        CommandMenu("Capture") {
            ForEach(QuickAction.all) { action in
                QuickActionButton(action: action)
                    .environment(dependencies)
                    .menuShortcut(dependencies.settings.shortcuts[action.id])
            }
        }

        CommandGroup(before: .toolbar) {
            ForEach(Array(AppTab.primary.enumerated()), id: \.element) { index, tab in
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
