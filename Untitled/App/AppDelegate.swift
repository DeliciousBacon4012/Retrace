import AppKit

/// Handles app lifecycle events that SwiftUI does not expose.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let dependencies = AppDependencies.live()

    func applicationDidFinishLaunching(_ notification: Notification) {
        dependencies.start()
        #if DEBUG
        // Lets automated checks open the editor: `open Untitled.app --args -UntitledDebugOpenImage <path>`.
        if let path = UserDefaults.standard.string(forKey: "UntitledDebugOpenImage") {
            dependencies.editor.open(fileAt: URL(fileURLWithPath: path))
        }
        #endif
    }

    /// Keep running in the menu bar after the main window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
