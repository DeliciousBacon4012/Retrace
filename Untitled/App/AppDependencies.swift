import Foundation
import OSLog
import Observation

/// Builds every service once and hands it to the views that need it.
///
/// Views get this through the SwiftUI environment. Previews and tests use `preview()`
/// so nothing touches real system settings.
@Observable
final class AppDependencies {
    let settings: SettingsStore
    let permissions: any PermissionProviding
    let launchAtLogin: any LaunchAtLoginControlling
    let dockIcon: any DockIconControlling
    let clipboard: any ClipboardWriting
    let library: CaptureLibrary
    let capture: CaptureCoordinator
    let recording: RecordingCoordinator
    let shortcuts: GlobalShortcuts
    let editor: EditorPresenter

    init(
        settings: SettingsStore,
        permissions: any PermissionProviding,
        launchAtLogin: any LaunchAtLoginControlling,
        dockIcon: any DockIconControlling,
        clipboard: any ClipboardWriting
    ) {
        self.settings = settings
        self.permissions = permissions
        self.launchAtLogin = launchAtLogin
        self.dockIcon = dockIcon
        self.clipboard = clipboard
        library = CaptureLibrary(folder: settings.saveFolderURL)
        let editor = EditorPresenter(settings: settings, clipboard: clipboard)
        self.editor = editor
        let quickAccess = QuickAccessController(settings: settings, clipboard: clipboard)
        quickAccess.onAnnotate = { [weak editor] capture in editor?.open(capture) }
        let capture = CaptureCoordinator(
            settings: settings,
            permissions: permissions,
            capturer: ScreenCaptureKitService(),
            storage: FileCaptureStorage(),
            clipboard: clipboard,
            quickAccess: quickAccess,
            editor: editor
        )
        self.capture = capture
        let recording = RecordingCoordinator(
            settings: settings,
            permissions: permissions,
            storage: FileCaptureStorage(),
            clipboard: clipboard,
            quickAccess: quickAccess
        )
        self.recording = recording
        shortcuts = GlobalShortcuts(settings: settings) { [weak capture, weak recording] actionID in
            guard let action = QuickAction.all.first(where: { $0.id == actionID }) else { return }
            if let mode = action.captureMode {
                Task { await capture?.capture(mode) }
            } else if let mode = action.recordingMode {
                Task { await recording?.toggle(mode) }
            }
        }
    }

    static func live() -> AppDependencies {
        AppDependencies(
            settings: SettingsStore(),
            permissions: SystemPermissionService(),
            launchAtLogin: SystemLaunchAtLoginService(),
            dockIcon: SystemDockIconService(),
            clipboard: SystemClipboard()
        )
    }

    /// Call once the app has finished launching.
    func start() {
        followDockIconSetting()
        library.start()
        followSaveFolderSetting()
        shortcuts.start()
        Log.app.info("Untitled \(Bundle.main.displayVersion, privacy: .public) started")
    }

    /// Applies the Dock icon setting now and again whenever it changes.
    private func followDockIconSetting() {
        withObservationTracking {
            dockIcon.setVisible(settings.showsDockIcon)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.followDockIconSetting()
            }
        }
    }

    /// Points the library at the save folder whenever it changes.
    private func followSaveFolderSetting() {
        let folder = withObservationTracking {
            settings.saveFolderURL
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.followSaveFolderSetting()
            }
        }
        library.setFolder(folder)
    }
}

#if DEBUG
extension AppDependencies {
    static func preview(screenRecording: PermissionStatus = .notGranted) -> AppDependencies {
        AppDependencies(
            settings: SettingsStore(defaults: UserDefaults(suiteName: "preview") ?? .standard),
            permissions: PreviewPermissionService(status: screenRecording),
            launchAtLogin: PreviewLaunchAtLoginService(),
            dockIcon: PreviewDockIconService(),
            clipboard: PreviewClipboard()
        )
    }
}
#endif
