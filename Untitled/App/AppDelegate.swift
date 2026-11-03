import AppKit

/// Handles app lifecycle events that SwiftUI does not expose.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let dependencies = AppDependencies.live()
    let launch = LaunchContext()

    func applicationDidFinishLaunching(_ notification: Notification) {
        dependencies.start()
        Task.detached(priority: .utility) { ReplayWriter.removeLeftovers() }
        launch.finishLaunching(opensWindowSetting: dependencies.settings.opensWindowAtLaunch)
        #if DEBUG
        // Lets automated checks open the editor: `open Untitled.app --args -UntitledDebugOpenImage <path>`.
        if let path = UserDefaults.standard.string(forKey: "UntitledDebugOpenImage") {
            dependencies.editor.open(fileAt: URL(fileURLWithPath: path))
        }
        #endif
    }

    /// Images opened from Finder, the Dock, or `open -a Untitled` go to the editor.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.isFileURL {
            dependencies.editor.open(fileAt: url)
        }
    }

    /// Clicking the Dock icon with nothing open brings back the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { launch.opensMainWindow = true }
        return false
    }

    /// Keep running in the menu bar after the main window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
