import ServiceManagement

/// Turns "open at login" on and off.
protocol LaunchAtLoginControlling: AnyObject {
    var isEnabled: Bool { get }
    /// True when macOS needs the person to approve the login item in System Settings.
    var requiresApproval: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

final class SystemLaunchAtLoginService: LaunchAtLoginControlling {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

#if DEBUG
/// A stand-in for previews and tests.
final class PreviewLaunchAtLoginService: LaunchAtLoginControlling {
    var isEnabled = false
    var requiresApproval = false

    func setEnabled(_ enabled: Bool) throws {
        isEnabled = enabled
    }
}
#endif
