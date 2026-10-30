import Observation

/// State and actions for the Home screen.
@Observable
final class HomeViewModel {
    private(set) var screenRecording: PermissionStatus

    @ObservationIgnored private let permissions: any PermissionProviding

    init(permissions: any PermissionProviding) {
        self.permissions = permissions
        screenRecording = permissions.screenRecordingStatus
    }

    var availableCount: Int { FeatureCatalog.all.filter(\.isAvailable).count }
    var plannedCount: Int { FeatureCatalog.all.count }

    /// Re-reads permission status, for example when the app becomes active again.
    func refresh() {
        screenRecording = permissions.screenRecordingStatus
    }

    func requestScreenRecording() {
        permissions.requestScreenRecordingAccess()
        refresh()
    }

    func openScreenRecordingSettings() {
        permissions.openScreenRecordingSettings()
    }
}
