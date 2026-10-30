import Foundation
import OSLog
import Observation

/// Login item state for the General pane, with errors turned into readable messages.
@Observable
final class GeneralSettingsViewModel {
    private(set) var launchesAtLogin: Bool
    private(set) var message: String?

    @ObservationIgnored private let launchAtLogin: any LaunchAtLoginControlling

    init(launchAtLogin: any LaunchAtLoginControlling) {
        self.launchAtLogin = launchAtLogin
        launchesAtLogin = launchAtLogin.isEnabled
    }

    func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            try launchAtLogin.setEnabled(enabled)
            message = nil
        } catch {
            Log.settings.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
            message = String(localized: "Couldn't change the login item. \(error.localizedDescription)")
        }

        launchesAtLogin = launchAtLogin.isEnabled
        if launchAtLogin.requiresApproval {
            message = String(localized: "Approve Untitled in System Settings › General › Login Items.")
        }
    }
}
