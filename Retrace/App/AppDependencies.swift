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
    let contentIndex = LibraryContentIndex()
    let capture: CaptureCoordinator
    let recording: RecordingCoordinator
    let replay: ReplayCoordinator
    let quickAccess: QuickAccessController
    let shortcuts: GlobalShortcuts
    let editor: EditorPresenter
    let pins: PinController
    /// The short notices at the top of the screen, shared so they never stack up.
    let toasts: CaptureToastController
    /// Text read by Capture Text, for Recents and the menu bar.
    let textHistory: TextHistory
    /// The originals of captures saved over in the editor.
    let versions: CaptureVersions
    /// Everything copied in any app, for the Clipboard view.
    let clipboardHistory: ClipboardHistory
    let memory = MemoryMonitor()

    init(
        settings: SettingsStore,
        permissions: any PermissionProviding,
        launchAtLogin: any LaunchAtLoginControlling,
        dockIcon: any DockIconControlling,
        clipboard: any ClipboardWriting,
        textHistoryFile: URL? = TextHistory.defaultFileURL,
        originalsFolder: URL? = CaptureVersions.defaultFolder,
        clipboardFolder: URL? = ClipboardHistory.defaultFolder
    ) {
        self.settings = settings
        self.permissions = permissions
        self.launchAtLogin = launchAtLogin
        self.dockIcon = dockIcon
        self.clipboard = clipboard
        library = CaptureLibrary(folders: settings.saveFolderURLs)
        let toasts = CaptureToastController(settings: settings, permissions: permissions)
        self.toasts = toasts
        let textHistory = TextHistory(settings: settings, fileURL: textHistoryFile)
        self.textHistory = textHistory
        clipboardHistory = ClipboardHistory(settings: settings, clipboard: clipboard, folder: clipboardFolder)
        let versions = CaptureVersions(folder: originalsFolder)
        self.versions = versions
        let editor = EditorPresenter(settings: settings, clipboard: clipboard, textHistory: textHistory, versions: versions)
        self.editor = editor
        let pins = PinController(clipboard: clipboard)
        pins.onEdit = { [weak editor] capture in editor?.open(capture) }
        self.pins = pins
        let quickAccess = QuickAccessController(settings: settings, clipboard: clipboard)
        self.quickAccess = quickAccess
        quickAccess.onAnnotate = { [weak editor] capture in editor?.open(capture) }
        quickAccess.onPin = { [weak pins] capture in pins?.pin(capture) }
        let capture = CaptureCoordinator(
            settings: settings,
            permissions: permissions,
            capturer: ScreenCaptureKitService(),
            storage: FileCaptureStorage(),
            clipboard: clipboard,
            quickAccess: quickAccess,
            editor: editor,
            toasts: toasts,
            textHistory: textHistory
        )
        self.capture = capture
        quickAccess.onSave = { [weak capture] image in await capture?.save(image) }
        let replay = ReplayCoordinator(settings: settings, permissions: permissions, storage: FileCaptureStorage(), clipboard: clipboard, quickAccess: quickAccess, toasts: toasts)
        self.replay = replay
        let recording = RecordingCoordinator(
            settings: settings,
            permissions: permissions,
            replay: replay,
            storage: FileCaptureStorage(),
            clipboard: clipboard,
            quickAccess: quickAccess,
            toasts: toasts
        )
        self.recording = recording
        shortcuts = GlobalShortcuts(settings: settings) { [weak settings, weak capture, weak recording, weak replay] actionID in
            guard let settings, let action = QuickAction.withID(actionID, saveLastDurations: settings.saveLastDurations) else { return }
            Self.perform(action, capture: capture, recording: recording, replay: replay)
        }
    }

    /// Runs any quick action. Menus, global shortcuts, and buttons all come through here.
    func perform(_ action: QuickAction) {
        Self.perform(action, capture: capture, recording: recording, replay: replay)
    }

    private static func perform(_ action: QuickAction, capture: CaptureCoordinator?, recording: RecordingCoordinator?, replay: ReplayCoordinator?) {
        if action.isScreenshot {
            Task { await capture?.run(action) }
        } else if action.opensClipboard {
            capture?.openFromClipboard()
        } else if let mode = action.recordingMode {
            Task { await recording?.toggle(mode) }
        } else if action.savesReplay {
            Task { await replay?.saveClip(lastSeconds: action.saveLastSeconds) }
        }
    }

    static func live() -> AppDependencies {
        // Before anything reads settings or opens its data folder.
        LegacyDataMigrator.runIfNeeded()
        return AppDependencies(
            settings: SettingsStore(),
            permissions: SystemPermissionService(),
            launchAtLogin: SystemLaunchAtLoginService(),
            dockIcon: SystemDockIconService(),
            clipboard: SystemClipboard()
        )
    }

    /// Keeps the Library's content index in step with its files and with Settings.
    private func followContentIndexSetting() {
        let (enabled, items) = withObservationTracking {
            (settings.indexesLibraryContent, library.items)
        } onChange: { [weak self] in
            Task { @MainActor in self?.followContentIndexSetting() }
        }
        if enabled {
            contentIndex.update(with: items)
        } else if contentIndex.indexedCount > 0 || contentIndex.isIndexing {
            contentIndex.removeAll()
        }
    }

    /// Call once the app has finished launching.
    func start() {
        followDockIconSetting()
        library.start()
        followSaveFolderSetting()
        shortcuts.start()
        replay.start()
        clipboardHistory.start()
        followContentIndexSetting()
        followThumbnailMemorySetting()
        memory.onPressure = { [weak self] pressure in self?.relieveMemory(pressure) }
        memory.start()
        TextRecognizer.prepare()
        Log.app.info("Retrace \(Bundle.main.displayVersion, privacy: .public) started")
    }

    /// Lets go of caches, cheapest to rebuild first: thumbnails, then the editor's spare
    /// blur and pixelation layers. Each comes back on its own when it's next needed.
    func relieveMemory(_ pressure: MemoryPressure = .critical) {
        ThumbnailCache.shared.removeAll()
        if pressure == .critical {
            editor.dropSpareCaches()
        }
    }

    private func followThumbnailMemorySetting() {
        withObservationTracking {
            ThumbnailCache.shared.setMemoryLimit(megabytes: settings.thumbnailMemoryMB)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.followThumbnailMemorySetting()
            }
        }
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

    /// Keeps the Library in sync with every configured save location.
    private func followSaveFolderSetting() {
        let folders = withObservationTracking {
            settings.saveFolderURLs
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.followSaveFolderSetting()
            }
        }
        library.setFolders(folders)
    }
}

/// Resolves the session's optional capture-menu destination against configured save locations.
enum CaptureDestinationSelection {
    static func folder(for selection: String?, in settings: SettingsStore) -> URL? {
        guard let selection, settings.saveFolderPaths.contains(selection) else { return nil }
        return URL(fileURLWithPath: selection, isDirectory: true)
    }

    static func activePath(for selection: String?, in settings: SettingsStore) -> String {
        guard let selection, settings.saveFolderPaths.contains(selection) else { return settings.saveFolderPath }
        return selection
    }

    static func selection(for path: String, defaultPath: String) -> String? {
        path == defaultPath ? nil : path
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
            clipboard: PreviewClipboard(),
            textHistoryFile: nil,
            originalsFolder: nil,
            clipboardFolder: nil
        )
    }
}
#endif
