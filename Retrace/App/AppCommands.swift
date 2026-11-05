import SwiftUI
import UniformTypeIdentifiers

/// Menu bar commands for the main window.
struct AppCommands: Commands {
    let dependencies: AppDependencies

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
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
            ForEach(QuickAction.all.filter(\.opensClipboard)) { action in
                QuickActionButton(action: action)
                    .environment(dependencies)
                    .keyboardShortcut("v", modifiers: [.command, .shift])
            }
            Button("Pin to Screen…") {
                dependencies.pins.pinFromFile()
            }
        }

        CommandGroup(before: .toolbar) {
            ForEach(Array(MainTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) { MainWindowRouter.shared.show(tab, using: openWindow) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
            }
            Divider()
        }

        // Every capture and recording, then Save Last. Opening the clipboard's image is under File.
        CommandMenu("Capture") {
            ForEach(QuickAction.all.filter { !$0.opensClipboard && !$0.savesReplay }) { action in
                QuickActionButton(action: action)
                    .environment(dependencies)
                    .menuShortcut(dependencies.settings.shortcuts[action.id])
            }
            Divider()
            SaveLastMenu()
                .environment(dependencies)
                .environment(dependencies.settings)
        }

        CommandGroup(replacing: .help) {
            if let url = URL(string: "https://github.com/DeliciousBacon4012/retrace") {
                Link("Retrace on GitHub", destination: url)
            }
        }
    }
}
