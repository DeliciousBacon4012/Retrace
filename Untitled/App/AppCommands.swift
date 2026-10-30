import SwiftUI

/// Menu bar commands for the main window.
struct AppCommands: Commands {
    let capture: CaptureCoordinator

    var body: some Commands {
        CommandMenu("Capture") {
            ForEach(QuickAction.all) { action in
                if let mode = action.captureMode {
                    Button(action.title) {
                        Task { await capture.capture(mode) }
                    }
                } else {
                    Button(action.title) {}
                        .disabled(true)
                }
            }
        }

        CommandGroup(replacing: .help) {
            if let url = URL(string: "https://github.com/DeliciousBacon4012/untitled-mac") {
                Link("Untitled on GitHub", destination: url)
            }
        }
    }
}
