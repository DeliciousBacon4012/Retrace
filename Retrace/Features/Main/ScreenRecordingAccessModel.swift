import Foundation
import Observation

/// Screen Recording access as the main window shows it, and the ways to fix it.
@Observable
final class ScreenRecordingAccessModel {
    private(set) var screenRecording: PermissionStatus
    private(set) var isChecking = false
    /// True after a manual check still found no access, so the screen can suggest a restart.
    private(set) var checkFoundNoAccess = false

    @ObservationIgnored private let permissions: any PermissionProviding

    init(permissions: any PermissionProviding) {
        self.permissions = permissions
        screenRecording = permissions.screenRecordingStatus
    }

    /// Re-reads permission status, for example when the app becomes active again.
    func refresh() {
        screenRecording = permissions.screenRecordingStatus
        if screenRecording == .granted {
            checkFoundNoAccess = false
        }
    }

    /// Checks every 1.5 seconds until access is granted or the screen goes away,
    /// so choosing "Later" in System Settings still gets noticed.
    func watchScreenRecording() async {
        while screenRecording == .notGranted, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1.5))
            refresh()
        }
    }

    func checkAgain() async {
        isChecking = true
        defer { isChecking = false }
        screenRecording = await permissions.confirmScreenRecordingAccess()
        checkFoundNoAccess = screenRecording == .notGranted
    }

    func requestScreenRecording() {
        permissions.requestScreenRecordingAccess()
        refresh()
    }

    func openScreenRecordingSettings() {
        permissions.openScreenRecordingSettings()
    }

    func restart() {
        AppRelauncher.relaunch()
    }
}
