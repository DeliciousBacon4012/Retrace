import AppKit
import OSLog

/// Shows or hides the app's Dock icon.
protocol DockIconControlling: AnyObject {
    func setVisible(_ visible: Bool)
}

final class SystemDockIconService: DockIconControlling {
    func setVisible(_ visible: Bool) {
        let policy: NSApplication.ActivationPolicy = visible ? .regular : .accessory
        guard NSApplication.shared.activationPolicy() != policy else { return }
        if !NSApplication.shared.setActivationPolicy(policy) {
            Log.app.error("Could not change the Dock icon visibility")
        }
    }
}

#if DEBUG
/// A stand-in for previews and tests.
final class PreviewDockIconService: DockIconControlling {
    func setVisible(_ visible: Bool) {}
}
#endif
