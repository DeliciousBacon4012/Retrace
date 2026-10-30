import AppKit
import OSLog

/// Quits the app and opens a fresh copy, for permissions that only apply after a restart.
enum AppRelauncher {
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error {
                Log.app.error("Relaunch failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            Task { @MainActor in
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
