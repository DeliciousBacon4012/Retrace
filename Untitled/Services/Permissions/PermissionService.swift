import AppKit
import CoreGraphics
import OSLog

/// Whether the app has been given a system permission.
nonisolated enum PermissionStatus: Sendable {
    case granted
    case notGranted
}

/// Checks and requests the system permissions the app needs.
protocol PermissionProviding: AnyObject {
    var screenRecordingStatus: PermissionStatus { get }
    /// Asks macOS for Screen Recording access. The system prompt only appears the first time.
    func requestScreenRecordingAccess()
    /// Opens the Screen Recording pane of System Settings.
    func openScreenRecordingSettings()
}

final class SystemPermissionService: PermissionProviding {
    var screenRecordingStatus: PermissionStatus {
        CGPreflightScreenCaptureAccess() ? .granted : .notGranted
    }

    func requestScreenRecordingAccess() {
        let granted = CGRequestScreenCaptureAccess()
        Log.permissions.info("Screen Recording request returned \(granted, privacy: .public)")
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            Log.permissions.error("Screen Recording settings URL is invalid")
            return
        }
        if !NSWorkspace.shared.open(url) {
            Log.permissions.error("Could not open System Settings")
        }
    }
}

#if DEBUG
/// A stand-in for previews and tests.
final class PreviewPermissionService: PermissionProviding {
    var screenRecordingStatus: PermissionStatus

    init(status: PermissionStatus = .notGranted) {
        screenRecordingStatus = status
    }

    func requestScreenRecordingAccess() {
        screenRecordingStatus = .granted
    }

    func openScreenRecordingSettings() {}
}
#endif
