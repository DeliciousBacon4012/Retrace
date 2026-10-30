import Foundation
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

    // MARK: Output

    var imageFormat = Defaults.imageFormat { didSet { save(imageFormat.rawValue, .imageFormat) } }
    var downscalesRetina = Defaults.downscalesRetina { didSet { save(downscalesRetina, .downscalesRetina) } }
    var saveFolderPath = Defaults.saveFolderPath { didSet { save(saveFolderPath, .saveFolderPath) } }
    var filenameTemplate = Defaults.filenameTemplate { didSet { save(filenameTemplate, .filenameTemplate) } }

    // MARK: Recording

    var videoCodec = Defaults.videoCodec { didSet { save(videoCodec.rawValue, .videoCodec) } }
    var framesPerSecond = Defaults.framesPerSecond { didSet { save(framesPerSecond, .framesPerSecond) } }
    var recordsSystemAudio = Defaults.recordsSystemAudio { didSet { save(recordsSystemAudio, .recordsSystemAudio) } }
    var recordsMicrophone = Defaults.recordsMicrophone { didSet { save(recordsMicrophone, .recordsMicrophone) } }
    var showsClicks = Defaults.showsClicks { didSet { save(showsClicks, .showsClicks) } }

    // MARK: Replay buffer

    var replayBufferSeconds = Defaults.replayBufferSeconds { didSet { save(replayBufferSeconds, .replayBufferSeconds) } }
    var replayDiskLimitGB = Defaults.replayDiskLimitGB { didSet { save(replayDiskLimitGB, .replayDiskLimitGB) } }

    // MARK: Storage

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
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
        copiesToClipboard = value(.copiesToClipboard, default: Defaults.copiesToClipboard)
        savesToFolder = value(.savesToFolder, default: Defaults.savesToFolder)
        showsQuickAccess = value(.showsQuickAccess, default: Defaults.showsQuickAccess)
        opensEditor = value(.opensEditor, default: Defaults.opensEditor)
        includesCursor = value(.includesCursor, default: Defaults.includesCursor)
        includesWindowShadow = value(.includesWindowShadow, default: Defaults.includesWindowShadow)
        overlayCorner = OverlayCorner(rawValue: value(.overlayCorner, default: "")) ?? Defaults.overlayCorner
        overlayAutoCloseSeconds = value(.overlayAutoCloseSeconds, default: Defaults.overlayAutoCloseSeconds)
        imageFormat = ImageFormat(rawValue: value(.imageFormat, default: "")) ?? Defaults.imageFormat
        downscalesRetina = value(.downscalesRetina, default: Defaults.downscalesRetina)
        saveFolderPath = value(.saveFolderPath, default: Defaults.saveFolderPath)
        filenameTemplate = value(.filenameTemplate, default: Defaults.filenameTemplate)
        videoCodec = VideoCodec(rawValue: value(.videoCodec, default: "")) ?? Defaults.videoCodec
        framesPerSecond = value(.framesPerSecond, default: Defaults.framesPerSecond)
        recordsSystemAudio = value(.recordsSystemAudio, default: Defaults.recordsSystemAudio)
        recordsMicrophone = value(.recordsMicrophone, default: Defaults.recordsMicrophone)
        showsClicks = value(.showsClicks, default: Defaults.showsClicks)
        replayBufferSeconds = value(.replayBufferSeconds, default: Defaults.replayBufferSeconds)
        replayDiskLimitGB = value(.replayDiskLimitGB, default: Defaults.replayDiskLimitGB)
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
        case copiesToClipboard
        case savesToFolder
        case showsQuickAccess
        case opensEditor
        case includesCursor
        case includesWindowShadow
        case overlayCorner
        case overlayAutoCloseSeconds
        case imageFormat
        case downscalesRetina
        case saveFolderPath
        case filenameTemplate
        case videoCodec
        case framesPerSecond
        case recordsSystemAudio
        case recordsMicrophone
        case showsClicks
        case replayBufferSeconds
        case replayDiskLimitGB
    }

    enum Defaults {
        static let showsDockIcon = true
        static let playsSounds = true
        static let copiesToClipboard = true
        static let savesToFolder = true
        static let showsQuickAccess = true
        static let opensEditor = false
        static let includesCursor = false
        static let includesWindowShadow = true
        static let overlayCorner = OverlayCorner.bottomLeft
        static let overlayAutoCloseSeconds = 0
        static let imageFormat = ImageFormat.png
        static let downscalesRetina = false
        static let filenameTemplate = "Untitled {date} at {time}"
        static let videoCodec = VideoCodec.hevc
        static let framesPerSecond = 60
        static let recordsSystemAudio = true
        static let recordsMicrophone = false
        static let showsClicks = false
        static let replayBufferSeconds = 60
        static let replayDiskLimitGB = 4

        static var saveFolderPath: String {
            let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            return pictures.appendingPathComponent("Untitled", isDirectory: true).path
        }
    }
}
