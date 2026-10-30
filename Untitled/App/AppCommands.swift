import SwiftUI

/// Menu bar commands for the main window.
struct AppCommands: Commands {
    let capture: CaptureCoordinator

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Capture") {
            ForEach(QuickAction.all) { action in
                if let mode = action.captureMode {
                    Button(action.title, systemImage: action.symbolName) {
                        Task { await capture.capture(mode) }
                    }
                    .labelStyle(.titleAndIcon)
                } else {
                    Button(action.title, systemImage: action.symbolName) {}
                        .labelStyle(.titleAndIcon)
                        .disabled(true)
                }
            }
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
