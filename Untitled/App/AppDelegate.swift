import AppKit

/// Handles app lifecycle events that SwiftUI does not expose.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let dependencies = AppDependencies.live()

    func applicationDidFinishLaunching(_ notification: Notification) {
        dependencies.start()
    }

    /// Keep running in the menu bar after the main window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
