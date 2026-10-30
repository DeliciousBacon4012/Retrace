import AppKit

/// Shows problems to the person in a standard alert, so failures never pass silently.
enum ErrorPresenter {
    static func present(_ error: any Error, recovery: String? = nil) {
        present(error.localizedDescription, recovery: recovery)
    }

    static func present(_ message: String, recovery: String? = nil) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        if let recovery {
            alert.informativeText = recovery
        }
        NSApplication.shared.activate()
        alert.runModal()
    }
}
