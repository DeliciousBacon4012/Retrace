import SwiftUI

/// Menu bar commands for the main window.
struct AppCommands: Commands {
    var body: some Commands {
        SidebarCommands()

        CommandMenu("Capture") {
            ForEach(QuickAction.all) { action in
                Button(action.title) {}
                    .disabled(true)
            }
        }

        CommandGroup(replacing: .help) {
            if let url = URL(string: "https://github.com/DeliciousBacon4012/untitled-mac") {
                Link("Untitled on GitHub", destination: url)
            }
        }
    }
}
