import AppKit
import Carbon.HIToolbox
import Foundation
import OSLog
import Observation

/// Typed, observable access to every user preference, persisted in `UserDefaults`.
///
/// Views read and bind to these properties directly. Each change is written straight away,
/// so nothing is lost if the app quits unexpectedly.
@Observable
final class SettingsStore {
    // MARK: General

    var showsDockIcon = Defaults.showsDockIcon { didSet { save(showsDockIcon, .showsDockIcon) } }
    var playsSounds = Defaults.playsSounds { didSet { save(playsSounds, .playsSounds) } }
    /// Opens the main window when you start Untitled yourself. Starting at login never does.
    var opensWindowAtLaunch = Defaults.opensWindowAtLaunch { didSet { save(opensWindowAtLaunch, .opensWindowAtLaunch) } }

    // MARK: After capture

    var copiesToClipboard = Defaults.copiesToClipboard { didSet { save(copiesToClipboard, .copiesToClipboard) } }
    var savesToFolder = Defaults.savesToFolder { didSet { save(savesToFolder, .savesToFolder) } }
    var showsQuickAccess = Defaults.showsQuickAccess { didSet { save(showsQuickAccess, .showsQuickAccess) } }
    var opensEditor = Defaults.opensEditor { didSet { save(opensEditor, .opensEditor) } }
    var includesCursor = Defaults.includesCursor { didSet { save(includesCursor, .includesCursor) } }
    var includesWindowShadow = Defaults.includesWindowShadow { didSet { save(includesWindowShadow, .includesWindowShadow) } }
    var overlayCorner = Defaults.overlayCorner { didSet { save(overlayCorner.rawValue, .overlayCorner) } }
    /// Seconds before the Quick Access overlay closes on its own. Zero means never.
    var overlayAutoCloseSeconds = Defaults.overlayAutoCloseSeconds { didSet { save(overlayAutoCloseSeconds, .overlayAutoCloseSeconds) } }
    /// How quickly Quick Access thumbnails glide in and fade away.
    var overlaySpeed = Defaults.overlaySpeed { didSet { save(overlaySpeed.rawValue, .overlaySpeed) } }
    var quickAccessLayout = Defaults.quickAccessLayout { didSet { save(quickAccessLayout.rawValue, .quickAccessLayout) } }
    var quickAccessSize = Defaults.quickAccessSize { didSet { save(quickAccessSize.rawValue, .quickAccessSize) } }
    /// The most thumbnails shown at once; older ones close first.
    var quickAccessMaxVisible = Defaults.quickAccessMaxVisible { didSet { save(quickAccessMaxVisible, .quickAccessMaxVisible) } }

    // MARK: Output

    var imageFormat = Defaults.imageFormat { didSet { save(imageFormat.rawValue, .imageFormat) } }
    var downscalesRetina = Defaults.downscalesRetina { didSet { save(downscalesRetina, .downscalesRetina) } }
    /// Quality for JPEG, HEIC, and AVIF, from 0 to 1.
    var imageQuality = Defaults.imageQuality { didSet { save(imageQuality, .imageQuality) } }
    /// Leaves EXIF, GPS, and device details out of every saved and exported image.
    var stripsMetadata = Defaults.stripsMetadata { didSet { save(stripsMetadata, .stripsMetadata) } }
    /// Removes descriptive metadata from recordings and replay clips.
    var stripsVideoMetadata = Defaults.stripsVideoMetadata { didSet { save(stripsVideoMetadata, .stripsVideoMetadata) } }
    var saveFolderPath = Defaults.saveFolderPath { didSet { save(saveFolderPath, .saveFolderPath) } }
    var filenameTemplate = Defaults.filenameTemplate { didSet { save(filenameTemplate, .filenameTemplate) } }

    // MARK: Recording

    var videoCodec = Defaults.videoCodec { didSet { save(videoCodec.rawValue, .videoCodec) } }
    var framesPerSecond = Defaults.framesPerSecond { didSet { save(framesPerSecond, .framesPerSecond) } }
    var recordsSystemAudio = Defaults.recordsSystemAudio { didSet { save(recordsSystemAudio, .recordsSystemAudio) } }
    var recordsMicrophone = Defaults.recordsMicrophone { didSet { save(recordsMicrophone, .recordsMicrophone) } }
    var showsClicks = Defaults.showsClicks { didSet { save(showsClicks, .showsClicks) } }

    // MARK: Replay buffer

    /// Whether the replay buffer runs, including after the next launch.
    var replayBufferEnabled = Defaults.replayBufferEnabled { didSet { save(replayBufferEnabled, .replayBufferEnabled) } }
    var replayBufferSeconds = Defaults.replayBufferSeconds { didSet { save(replayBufferSeconds, .replayBufferSeconds) } }
    var replayDiskLimitGB = Defaults.replayDiskLimitGB { didSet { save(replayDiskLimitGB, .replayDiskLimitGB) } }

    // MARK: Shortcuts

    /// Global shortcuts by `QuickAction` identifier. An action missing from the dictionary has none.
    var shortcuts = Defaults.shortcuts { didSet { saveShortcuts() } }

    // MARK: Storage

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    static var defaultShortcuts: [String: Shortcut] { Defaults.shortcuts }

    /// How captures are encoded when saved, following the Files & Privacy settings.
    func exportOptions(for scale: CGFloat) -> ExportOptions {
        var options = ExportOptions(format: imageFormat)
        options.quality = imageQuality
        options.stripsMetadata = stripsMetadata
        if downscalesRetina, scale > 1 {
            options.scalePercent = 100 / scale
        }
        return options
    }

    /// The folder captures are saved to, as a file URL.
    var saveFolderURL: URL {
        URL(fileURLWithPath: saveFolderPath, isDirectory: true)
    }

    /// Restores every preference to its default value.
    func resetToDefaults() {
        for key in Key.allCases {
            defaults.removeObject(forKey: key.rawValue)
        }
        load()
        Log.settings.info("Settings reset to defaults")
    }

    // MARK: Loading and saving

    private func load() {
        showsDockIcon = value(.showsDockIcon, default: Defaults.showsDockIcon)
        playsSounds = value(.playsSounds, default: Defaults.playsSounds)
        opensWindowAtLaunch = value(.opensWindowAtLaunch, default: Defaults.opensWindowAtLaunch)
        copiesToClipboard = value(.copiesToClipboard, default: Defaults.copiesToClipboard)
        savesToFolder = value(.savesToFolder, default: Defaults.savesToFolder)
        showsQuickAccess = value(.showsQuickAccess, default: Defaults.showsQuickAccess)
        opensEditor = value(.opensEditor, default: Defaults.opensEditor)
        includesCursor = value(.includesCursor, default: Defaults.includesCursor)
        includesWindowShadow = value(.includesWindowShadow, default: Defaults.includesWindowShadow)
        overlayCorner = OverlayCorner(rawValue: value(.overlayCorner, default: "")) ?? Defaults.overlayCorner
        overlayAutoCloseSeconds = value(.overlayAutoCloseSeconds, default: Defaults.overlayAutoCloseSeconds)
        overlaySpeed = OverlaySpeed(rawValue: value(.overlaySpeed, default: "")) ?? Defaults.overlaySpeed
        quickAccessLayout = QuickAccessLayout(rawValue: value(.quickAccessLayout, default: "")) ?? Defaults.quickAccessLayout
        quickAccessSize = QuickAccessSize(rawValue: value(.quickAccessSize, default: "")) ?? Defaults.quickAccessSize
        quickAccessMaxVisible = min(max(value(.quickAccessMaxVisible, default: Defaults.quickAccessMaxVisible), 1), 8)
        imageFormat = ImageFormat(rawValue: value(.imageFormat, default: "")) ?? Defaults.imageFormat
        downscalesRetina = value(.downscalesRetina, default: Defaults.downscalesRetina)
        imageQuality = value(.imageQuality, default: Defaults.imageQuality)
        stripsMetadata = value(.stripsMetadata, default: Defaults.stripsMetadata)
        stripsVideoMetadata = value(.stripsVideoMetadata, default: Defaults.stripsVideoMetadata)
        saveFolderPath = value(.saveFolderPath, default: Defaults.saveFolderPath)
        filenameTemplate = value(.filenameTemplate, default: Defaults.filenameTemplate)
        videoCodec = VideoCodec(rawValue: value(.videoCodec, default: "")) ?? Defaults.videoCodec
        framesPerSecond = value(.framesPerSecond, default: Defaults.framesPerSecond)
        recordsSystemAudio = value(.recordsSystemAudio, default: Defaults.recordsSystemAudio)
        recordsMicrophone = value(.recordsMicrophone, default: Defaults.recordsMicrophone)
        showsClicks = value(.showsClicks, default: Defaults.showsClicks)
        replayBufferEnabled = value(.replayBufferEnabled, default: Defaults.replayBufferEnabled)
        replayBufferSeconds = value(.replayBufferSeconds, default: Defaults.replayBufferSeconds)
        replayDiskLimitGB = value(.replayDiskLimitGB, default: Defaults.replayDiskLimitGB)
        shortcuts = loadShortcuts()
    }

    /// Stored shortcuts on top of the defaults. A stored `null` means the person cleared it,
    /// so actions added in later versions still get their default shortcut.
    private func loadShortcuts() -> [String: Shortcut] {
        guard let data = defaults.data(forKey: Key.shortcuts.rawValue) else { return Defaults.shortcuts }
        do {
            let stored = try JSONDecoder().decode([String: Shortcut?].self, from: data)
            var result = Defaults.shortcuts
            for (actionID, shortcut) in stored {
                result[actionID] = shortcut
            }
            return result
        } catch {
            Log.settings.error("Stored shortcuts were unreadable, using defaults: \(error.localizedDescription, privacy: .public)")
            return Defaults.shortcuts
        }
    }

    private func saveShortcuts() {
        do {
            var stored: [String: Shortcut?] = [:]
            for action in QuickAction.all {
                stored[action.id] = .some(shortcuts[action.id])
            }
            defaults.set(try JSONEncoder().encode(stored), forKey: Key.shortcuts.rawValue)
        } catch {
            Log.settings.error("Saving shortcuts failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Reads a stored value, falling back to the default when it is missing or has the wrong type.
    private func value<Value>(_ key: Key, default fallback: Value) -> Value {
        defaults.object(forKey: key.rawValue) as? Value ?? fallback
    }

    private func save(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }
}

// MARK: - Keys and defaults

private extension SettingsStore {
    enum Key: String, CaseIterable {
        case showsDockIcon
        case playsSounds
        case opensWindowAtLaunch
        case copiesToClipboard
        case savesToFolder
        case showsQuickAccess
        case opensEditor
        case includesCursor
        case includesWindowShadow
        case overlayCorner
        case overlayAutoCloseSeconds
        case overlaySpeed
        case quickAccessLayout
        case quickAccessSize
        case quickAccessMaxVisible
        case imageFormat
        case downscalesRetina
        case imageQuality
        case stripsMetadata
        case stripsVideoMetadata
        case saveFolderPath
        case filenameTemplate
        case videoCodec
        case framesPerSecond
        case recordsSystemAudio
        case recordsMicrophone
        case showsClicks
        case replayBufferEnabled
        case replayBufferSeconds
        case replayDiskLimitGB
        case shortcuts
    }

    enum Defaults {
        static let showsDockIcon = true
        static let playsSounds = true
        static let opensWindowAtLaunch = true
        static let copiesToClipboard = true
        static let savesToFolder = true
        static let showsQuickAccess = true
        static let opensEditor = false
        static let includesCursor = false
        static let includesWindowShadow = true
        static let overlayCorner = OverlayCorner.bottomLeft
        static let overlayAutoCloseSeconds = 0
        static let overlaySpeed = OverlaySpeed.normal
        static let quickAccessLayout = QuickAccessLayout.stack
        static let quickAccessSize = QuickAccessSize.medium
        static let quickAccessMaxVisible = 5
        static let imageFormat = ImageFormat.png
        static let downscalesRetina = false
        static let imageQuality = 0.85
        static let stripsMetadata = true
        static let stripsVideoMetadata = true
        static let filenameTemplate = "Untitled {date} at {time}"
        static let videoCodec = VideoCodec.hevc
        static let framesPerSecond = 60
        static let recordsSystemAudio = true
        static let recordsMicrophone = false
        static let showsClicks = false
        static let replayBufferEnabled = false
        static let replayBufferSeconds = 60
        static let replayDiskLimitGB = 4

        /// ⌥⇧⌘ plus the number macOS uses for the same kind of screenshot; recordings follow on 6 and 7.
        static let shortcuts: [String: Shortcut] = [
            "captureScreen": Shortcut(keyCode: UInt32(kVK_ANSI_3), modifiers: [.option, .shift, .command]),
            "captureArea": Shortcut(keyCode: UInt32(kVK_ANSI_4), modifiers: [.option, .shift, .command]),
            "captureWindow": Shortcut(keyCode: UInt32(kVK_ANSI_5), modifiers: [.option, .shift, .command]),
            "recordArea": Shortcut(keyCode: UInt32(kVK_ANSI_6), modifiers: [.option, .shift, .command]),
            "recordScreen": Shortcut(keyCode: UInt32(kVK_ANSI_7), modifiers: [.option, .shift, .command]),
            "saveReplay": Shortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: [.option, .shift, .command]),
        ]

        static var saveFolderPath: String {
            let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            return pictures.appendingPathComponent("Untitled", isDirectory: true).path
        }
    }
}
