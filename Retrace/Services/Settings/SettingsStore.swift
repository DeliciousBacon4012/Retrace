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
    /// Opens the main window when you start Retrace yourself. Starting at login never does.
    var opensWindowAtLaunch = Defaults.opensWindowAtLaunch { didSet { save(opensWindowAtLaunch, .opensWindowAtLaunch) } }

    // MARK: After capture

    var copiesToClipboard = Defaults.copiesToClipboard { didSet { save(copiesToClipboard, .copiesToClipboard) } }
    var savesToFolder = Defaults.savesToFolder { didSet { save(savesToFolder, .savesToFolder) } }
    var showsQuickAccess = Defaults.showsQuickAccess { didSet { save(showsQuickAccess, .showsQuickAccess) } }
    var opensEditor = Defaults.opensEditor { didSet { save(opensEditor, .opensEditor) } }
    var includesCursor = Defaults.includesCursor { didSet { save(includesCursor, .includesCursor) } }
    var includesWindowShadow = Defaults.includesWindowShadow { didSet { save(includesWindowShadow, .includesWindowShadow) } }
    /// Space around window captures, in points.
    var windowPadding = Defaults.windowPadding { didSet { save(windowPadding, .windowPadding) } }
    var windowBackground = Defaults.windowBackground { didSet { save(windowBackground.rawValue, .windowBackground) } }
    var overlayCorner = Defaults.overlayCorner { didSet { save(overlayCorner.rawValue, .overlayCorner) } }
    /// Seconds before the Quick Access overlay closes on its own. Zero means never.
    var overlayAutoCloseSeconds = Defaults.overlayAutoCloseSeconds { didSet { save(overlayAutoCloseSeconds, .overlayAutoCloseSeconds) } }
    /// How quickly Quick Access thumbnails glide in and fade away.
    var overlaySpeed = Defaults.overlaySpeed { didSet { save(overlaySpeed.rawValue, .overlaySpeed) } }
    var quickAccessLayout = Defaults.quickAccessLayout { didSet { save(quickAccessLayout.rawValue, .quickAccessLayout) } }
    var quickAccessSize = Defaults.quickAccessSize { didSet { save(quickAccessSize.rawValue, .quickAccessSize) } }
    var quickAccessAspectRatio = Defaults.quickAccessAspectRatio { didSet { save(quickAccessAspectRatio.rawValue, .quickAccessAspectRatio) } }
    /// The most thumbnails shown at once; older ones close first.
    var quickAccessMaxVisible = Defaults.quickAccessMaxVisible { didSet { save(quickAccessMaxVisible, .quickAccessMaxVisible) } }

    // MARK: Notifications

    var showsToasts = Defaults.showsToasts { didSet { save(showsToasts, .showsToasts) } }
    var toastPosition = Defaults.toastPosition { didSet { save(toastPosition.rawValue, .toastPosition) } }
    /// Seconds each kind of toast stays, for kinds changed from their default. Zero means until dismissed.
    /// Lines of captured text a toast shows.
    var toastPreviewLines = Defaults.toastPreviewLines { didSet { save(toastPreviewLines, .toastPreviewLines) } }
    var plainTextApp = Defaults.plainTextApp { didSet { save(plainTextApp.rawValue, .plainTextApp) } }
    /// Whether recognized text is copied with one line break between Vision's text lines.
    var keepsOCRLineBreaks = Defaults.keepsOCRLineBreaks { didSet { save(keepsOCRLineBreaks, .keepsOCRLineBreaks) } }
    /// How many captured text snippets to keep. Zero keeps none.
    var textHistoryLimit = Defaults.textHistoryLimit { didSet { save(textHistoryLimit, .textHistoryLimit) } }
    /// The choices offered in Settings › Advanced.
    static let textHistoryLimits = [0, 25, 50, 100, 250]
    /// How much memory Library and the Capture page may use for thumbnails, in megabytes.
    var thumbnailMemoryMB = Defaults.thumbnailMemoryMB { didSet { save(thumbnailMemoryMB, .thumbnailMemoryMB) } }
    static let thumbnailMemoryChoices = [64, 128, 256]
    private var storedToastSeconds: [String: Int] = [:] { didSet { save(storedToastSeconds, .toastSeconds) } }

    // MARK: Clipboard history

    /// Keeps what you copy in any app, for the Clipboard view.
    var keepsClipboardHistory = Defaults.keepsClipboardHistory { didSet { save(keepsClipboardHistory, .keepsClipboardHistory) } }
    var clipboardRetention = Defaults.clipboardRetention { didSet { save(clipboardRetention.rawValue, .clipboardRetention) } }
    /// Apps whose copies are never kept, by bundle identifier.
    var clipboardExcludedApps = Defaults.clipboardExcludedApps { didSet { save(clipboardExcludedApps, .clipboardExcludedApps) } }

    // MARK: Output

    var imageFormat = Defaults.imageFormat { didSet { save(imageFormat.rawValue, .imageFormat) } }
    var downscalesRetina = Defaults.downscalesRetina { didSet { save(downscalesRetina, .downscalesRetina) } }
    /// Quality for JPEG, HEIC, and AVIF, from 0 to 1.
    var imageQuality = Defaults.imageQuality { didSet { save(imageQuality, .imageQuality) } }
    /// Leaves EXIF, GPS, and device details out of every saved and exported image.
    var stripsMetadata = Defaults.stripsMetadata { didSet { save(stripsMetadata, .stripsMetadata) } }
    /// Removes descriptive metadata from recordings and replay clips.
    var stripsVideoMetadata = Defaults.stripsVideoMetadata { didSet { save(stripsVideoMetadata, .stripsVideoMetadata) } }
    /// The default used by shortcuts and captures when no session destination override is selected.
    var saveFolderPath = Defaults.saveFolderPath { didSet { save(saveFolderPath, .saveFolderPath) } }
    /// Configured folders, in the order they were added. Removing one never deletes its files.
    private(set) var saveFolderPaths = [Defaults.saveFolderPath] { didSet { save(saveFolderPaths, .saveFolderPaths) } }
    /// Optional destination selected in the capture menu for this app session; nil uses the configured default.
    var captureDestinationOverridePath: String?
    var filenameTemplate = Defaults.filenameTemplate { didSet { save(filenameTemplate, .filenameTemplate) } }

    // MARK: Recording

    var videoCodec = Defaults.videoCodec { didSet { save(videoCodec.rawValue, .videoCodec) } }
    var framesPerSecond = Defaults.framesPerSecond { didSet { save(framesPerSecond, .framesPerSecond) } }
    var recordsSystemAudio = Defaults.recordsSystemAudio { didSet { save(recordsSystemAudio, .recordsSystemAudio) } }
    var recordsMicrophone = Defaults.recordsMicrophone { didSet { save(recordsMicrophone, .recordsMicrophone) } }
    var showsClicks = Defaults.showsClicks { didSet { save(showsClicks, .showsClicks) } }
    /// Reads Library images on this Mac so search and Find Similar can use them.
    var indexesLibraryContent = Defaults.indexesLibraryContent { didSet { save(indexesLibraryContent, .indexesLibraryContent) } }
    var videoColor = Defaults.videoColor { didSet { save(videoColor.rawValue, .videoColor) } }
    var videoQuality = Defaults.videoQuality { didSet { save(videoQuality.rawValue, .videoQuality) } }
    var videoEncoder = Defaults.videoEncoder { didSet { save(videoEncoder.rawValue, .videoEncoder) } }
    /// How many frames ScreenCaptureKit may hold at once. More rides out busy moments; fewer uses less memory.
    var captureQueueDepth = Defaults.captureQueueDepth { didSet { save(captureQueueDepth, .captureQueueDepth) } }
    static let captureQueueDepthRange = 3...8

    /// The preset every recording setting matches, or nil when they've been mixed by hand.
    var recordingPreset: RecordingPreset? {
        RecordingPreset.allCases.first { preset in
            preset.codec == videoCodec && preset.framesPerSecond == framesPerSecond
                && preset.quality == videoQuality && preset.encoder == videoEncoder
                && preset.color == videoColor && preset.queueDepth == captureQueueDepth
        }
    }

    func apply(_ preset: RecordingPreset) {
        videoCodec = preset.codec
        framesPerSecond = preset.framesPerSecond
        videoQuality = preset.quality
        videoEncoder = preset.encoder
        videoColor = preset.color
        captureQueueDepth = preset.queueDepth
    }

    /// Retrace's own notices stay hidden while recording. They're never in the movie either way.
    var hidesNoticesWhileRecording = Defaults.hidesNoticesWhileRecording { didSet { save(hidesNoticesWhileRecording, .hidesNoticesWhileRecording) } }
    var cursorBlurEnabled = Defaults.cursorBlurEnabled { didSet { save(cursorBlurEnabled, .cursorBlurEnabled) } }
    var cursorBlurMode = Defaults.cursorBlurMode { didSet { save(cursorBlurMode.rawValue, .cursorBlurMode) } }
    /// How long the shutter stays open, as a share of one frame. 0.5 is film's 180° shutter.
    var cursorBlurAmount = Defaults.cursorBlurAmount { didSet { save(cursorBlurAmount, .cursorBlurAmount) } }
    static let cursorBlurAmountRange = 0.1...2.0
    var replayFramesPerSecond = Defaults.replayFramesPerSecond { didSet { save(replayFramesPerSecond, .replayFramesPerSecond) } }
    static let replayFrameRateChoices = [15, 24, 30, 60]
    var replayUsesFullResolution = Defaults.replayUsesFullResolution { didSet { save(replayUsesFullResolution, .replayUsesFullResolution) } }
    var replayQuality = Defaults.replayQuality { didSet { save(replayQuality.rawValue, .replayQuality) } }
    /// Shows a red dot and the elapsed time in the menu bar while recording.
    var showsRecordingTimeInMenuBar = Defaults.showsRecordingTimeInMenuBar { didSet { save(showsRecordingTimeInMenuBar, .showsRecordingTimeInMenuBar) } }
    /// Seconds to count down before a recording starts. Zero starts right away.
    var recordingCountdownSeconds = Defaults.recordingCountdownSeconds { didSet { save(recordingCountdownSeconds, .recordingCountdownSeconds) } }

    // MARK: Replay buffer

    /// Whether the replay buffer runs, including after the next launch.
    var replayBufferEnabled = Defaults.replayBufferEnabled { didSet { save(replayBufferEnabled, .replayBufferEnabled) } }
    var replayBufferSeconds = Defaults.replayBufferSeconds { didSet { save(replayBufferSeconds, .replayBufferSeconds) } }
    var replayDiskLimitGB = Defaults.replayDiskLimitGB { didSet { save(replayDiskLimitGB, .replayDiskLimitGB) } }
    /// The lengths offered under Save Last, in seconds, shortest first.
    private(set) var saveLastDurations = Defaults.saveLastDurations { didSet { save(saveLastDurations, .saveLastDurations) } }

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

    /// The most Save Last lengths kept, so the menu stays short.
    static let maximumSaveLastDurations = 8
    /// The longest Save Last length, matching the longest buffer.
    static let longestSaveLastDuration = 600

    /// Adds a Save Last length, ignoring repeats and anything out of range.
    func addSaveLastDuration(_ seconds: Int) {
        guard saveLastDurations.count < Self.maximumSaveLastDurations else { return }
        saveLastDurations = Self.cleaned(saveLastDurations + [seconds])
    }

    /// Removes a Save Last length and its shortcut.
    func removeSaveLastDuration(_ seconds: Int) {
        saveLastDurations.removeAll { $0 == seconds }
        shortcuts[QuickAction.saveLast(seconds).id] = nil
    }

    /// Sorted, without repeats, each from 1 second to 10 minutes, and no more than the menu holds.
    private static func cleaned(_ durations: [Int]) -> [Int] {
        let valid = Set(durations.filter { (1...longestSaveLastDuration).contains($0) })
        return Array(valid.sorted().prefix(maximumSaveLastDurations))
    }

    /// How long a kind of toast stays, in seconds. Zero means until it's clicked.
    func toastSeconds(for kind: ToastKind) -> Int {
        storedToastSeconds[kind.rawValue] ?? kind.defaultSeconds
    }

    static let imageQualityChoices = 0.3...1.0
    static let frameRateChoices = [24, 30, 60, 120]
    static let recordingCountdownChoices = [0, 3, 5]
    static let overlayAutoCloseChoices = [0, 5, 10, 30, 60]
    static let replayBufferDurationChoices = [15, 30, 60, 120, 300, 600]
    static let replayDiskLimitChoices = [1, 2, 4, 8, 16]

    func setToastSeconds(_ seconds: Int, for kind: ToastKind) {
        storedToastSeconds[kind.rawValue] = seconds == kind.defaultSeconds ? nil : seconds
    }

    /// The currently selected folder captures are saved to.
    var saveFolderURL: URL {
        URL(fileURLWithPath: saveFolderPath, isDirectory: true)
    }

    /// All configured destinations in their menu and Library order.
    var saveFolderURLs: [URL] {
        saveFolderPaths.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    func setDefaultSaveFolder(_ path: String) {
        let normalized = Self.standardizedSaveFolderPath(path)
        guard saveFolderPaths.contains(normalized) else { return }
        saveFolderPath = normalized
    }

    /// Adds a folder without changing the current destination or moving any files.
    @discardableResult
    func addSaveFolder(_ url: URL) -> Bool {
        let path = Self.standardizedSaveFolderPath(url.path(percentEncoded: false))
        guard !saveFolderPaths.contains(path) else { return false }
        saveFolderPaths.append(path)
        return true
    }

    /// Stops including a folder in Retrace's Library. Its contents remain untouched on disk.
    func removeSaveFolder(_ path: String) {
        guard saveFolderPaths.count > 1 else { return }
        let normalized = Self.standardizedSaveFolderPath(path)
        guard let index = saveFolderPaths.firstIndex(of: normalized) else { return }
        let wasDefault = saveFolderPath == normalized
        saveFolderPaths.remove(at: index)
        if captureDestinationOverridePath == normalized {
            captureDestinationOverridePath = nil
        }
        if wasDefault, let replacement = saveFolderPaths.first {
            saveFolderPath = replacement
        }
    }

    /// Disambiguates folders that share a name while keeping the common case compact.
    func saveFolderDisplayName(for path: String) -> String {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        if Self.standardizedSaveFolderPath(path) == Self.standardizedSaveFolderPath(Defaults.saveFolderPath) {
            return String(localized: "Pictures › Retrace")
        }
        let sameName = saveFolderPaths.filter {
            URL(fileURLWithPath: $0, isDirectory: true).lastPathComponent == url.lastPathComponent
        }
        guard sameName.count > 1 else { return url.lastPathComponent }
        return "\(url.lastPathComponent) — \(url.deletingLastPathComponent().lastPathComponent)"
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
        windowPadding = min(max(value(.windowPadding, default: Defaults.windowPadding), 0), 200)
        windowBackground = WindowBackground(rawValue: value(.windowBackground, default: "")) ?? Defaults.windowBackground
        overlayCorner = OverlayCorner(rawValue: value(.overlayCorner, default: "")) ?? Defaults.overlayCorner
        overlayAutoCloseSeconds = Self.supportedChoice(
            value(.overlayAutoCloseSeconds, default: Defaults.overlayAutoCloseSeconds),
            in: Self.overlayAutoCloseChoices,
            fallback: Defaults.overlayAutoCloseSeconds
        )
        overlaySpeed = OverlaySpeed(rawValue: value(.overlaySpeed, default: "")) ?? Defaults.overlaySpeed
        quickAccessLayout = QuickAccessLayout(rawValue: value(.quickAccessLayout, default: "")) ?? Defaults.quickAccessLayout
        quickAccessSize = QuickAccessSize(rawValue: value(.quickAccessSize, default: "")) ?? Defaults.quickAccessSize
        quickAccessAspectRatio = QuickAccessAspectRatio(rawValue: value(.quickAccessAspectRatio, default: "")) ?? Defaults.quickAccessAspectRatio
        quickAccessMaxVisible = min(max(value(.quickAccessMaxVisible, default: Defaults.quickAccessMaxVisible), 1), 8)
        showsToasts = value(.showsToasts, default: Defaults.showsToasts)
        toastPosition = ToastPosition(rawValue: value(.toastPosition, default: "")) ?? Defaults.toastPosition
        toastPreviewLines = min(max(value(.toastPreviewLines, default: Defaults.toastPreviewLines), 1), 5)
        plainTextApp = PlainTextApp(rawValue: value(.plainTextApp, default: "")) ?? Defaults.plainTextApp
        keepsOCRLineBreaks = value(.keepsOCRLineBreaks, default: Defaults.keepsOCRLineBreaks)
        let limit = value(.textHistoryLimit, default: Defaults.textHistoryLimit)
        textHistoryLimit = Self.textHistoryLimits.contains(limit) ? limit : Defaults.textHistoryLimit
        keepsClipboardHistory = value(.keepsClipboardHistory, default: Defaults.keepsClipboardHistory)
        clipboardRetention = ClipboardRetention(rawValue: value(.clipboardRetention, default: "")) ?? Defaults.clipboardRetention
        clipboardExcludedApps = value(.clipboardExcludedApps, default: Defaults.clipboardExcludedApps)
        if !defaults.bool(forKey: "trimmedFormerExcludedApps") {
            defaults.set(true, forKey: "trimmedFormerExcludedApps")
            let trimmed = clipboardExcludedApps.filter { !Defaults.formerDefaultExcludedApps.contains($0) }
            if trimmed != clipboardExcludedApps { clipboardExcludedApps = trimmed }
        }
        let thumbnailMemory = value(.thumbnailMemoryMB, default: Defaults.thumbnailMemoryMB)
        thumbnailMemoryMB = Self.thumbnailMemoryChoices.contains(thumbnailMemory) ? thumbnailMemory : Defaults.thumbnailMemoryMB
        // Keep only known kinds with a time Settings offers, so the picker always shows a choice.
        storedToastSeconds = value(.toastSeconds, default: [String: Int]()).filter { key, seconds in
            ToastKind(rawValue: key) != nil && ToastKind.secondsChoices.contains(seconds)
        }
        imageFormat = ImageFormat(rawValue: value(.imageFormat, default: "")) ?? Defaults.imageFormat
        downscalesRetina = value(.downscalesRetina, default: Defaults.downscalesRetina)
        let storedImageQuality = value(.imageQuality, default: Defaults.imageQuality)
        imageQuality = storedImageQuality.isFinite
            ? min(max(storedImageQuality, Self.imageQualityChoices.lowerBound), Self.imageQualityChoices.upperBound)
            : Defaults.imageQuality
        stripsMetadata = value(.stripsMetadata, default: Defaults.stripsMetadata)
        stripsVideoMetadata = value(.stripsVideoMetadata, default: Defaults.stripsVideoMetadata)
        saveFolderPath = Self.standardizedSaveFolderPath(value(.saveFolderPath, default: Defaults.saveFolderPath))
        let storedSaveFolders: [String] = value(.saveFolderPaths, default: [])
        saveFolderPaths = Self.cleanedSaveFolderPaths(storedSaveFolders, including: saveFolderPath)
        filenameTemplate = value(.filenameTemplate, default: Defaults.filenameTemplate)
        videoCodec = VideoCodec(rawValue: value(.videoCodec, default: "")) ?? Defaults.videoCodec
        framesPerSecond = Self.supportedChoice(
            value(.framesPerSecond, default: Defaults.framesPerSecond),
            in: Self.frameRateChoices,
            fallback: Defaults.framesPerSecond
        )
        recordsSystemAudio = value(.recordsSystemAudio, default: Defaults.recordsSystemAudio)
        recordsMicrophone = value(.recordsMicrophone, default: Defaults.recordsMicrophone)
        showsClicks = value(.showsClicks, default: Defaults.showsClicks)
        indexesLibraryContent = value(.indexesLibraryContent, default: Defaults.indexesLibraryContent)
        hidesNoticesWhileRecording = value(.hidesNoticesWhileRecording, default: Defaults.hidesNoticesWhileRecording)
        videoColor = VideoColor(rawValue: value(.videoColor, default: "")) ?? Defaults.videoColor
        videoQuality = VideoQuality(rawValue: value(.videoQuality, default: "")) ?? Defaults.videoQuality
        videoEncoder = VideoEncoderChoice(rawValue: value(.videoEncoder, default: "")) ?? Defaults.videoEncoder
        captureQueueDepth = min(max(value(.captureQueueDepth, default: Defaults.captureQueueDepth), Self.captureQueueDepthRange.lowerBound), Self.captureQueueDepthRange.upperBound)
        cursorBlurEnabled = value(.cursorBlurEnabled, default: Defaults.cursorBlurEnabled)
        cursorBlurMode = CursorBlurMode(rawValue: value(.cursorBlurMode, default: "")) ?? Defaults.cursorBlurMode
        cursorBlurAmount = min(max(value(.cursorBlurAmount, default: Defaults.cursorBlurAmount), Self.cursorBlurAmountRange.lowerBound), Self.cursorBlurAmountRange.upperBound)
        replayFramesPerSecond = Self.supportedChoice(
            value(.replayFramesPerSecond, default: Defaults.replayFramesPerSecond),
            in: Self.replayFrameRateChoices,
            fallback: Defaults.replayFramesPerSecond
        )
        replayUsesFullResolution = value(.replayUsesFullResolution, default: Defaults.replayUsesFullResolution)
        let storedReplayQuality = VideoQuality(rawValue: value(.replayQuality, default: "")) ?? Defaults.replayQuality
        replayQuality = VideoQuality.replayChoices.contains(storedReplayQuality) ? storedReplayQuality : Defaults.replayQuality
        showsRecordingTimeInMenuBar = value(.showsRecordingTimeInMenuBar, default: Defaults.showsRecordingTimeInMenuBar)
        recordingCountdownSeconds = Self.supportedChoice(
            value(.recordingCountdownSeconds, default: Defaults.recordingCountdownSeconds),
            in: Self.recordingCountdownChoices,
            fallback: Defaults.recordingCountdownSeconds
        )
        replayBufferEnabled = value(.replayBufferEnabled, default: Defaults.replayBufferEnabled)
        replayBufferSeconds = Self.supportedChoice(
            value(.replayBufferSeconds, default: Defaults.replayBufferSeconds),
            in: Self.replayBufferDurationChoices,
            fallback: Defaults.replayBufferSeconds
        )
        replayDiskLimitGB = Self.supportedChoice(
            value(.replayDiskLimitGB, default: Defaults.replayDiskLimitGB),
            in: Self.replayDiskLimitChoices,
            fallback: Defaults.replayDiskLimitGB
        )
        saveLastDurations = Self.cleaned(value(.saveLastDurations, default: Defaults.saveLastDurations))
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
            // Only actions that still exist are kept, so a removed Save Last length leaves nothing behind.
            for action in QuickAction.all + saveLastDurations.map(QuickAction.saveLast) {
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

    private static func supportedChoice<Value: Equatable>(_ value: Value, in choices: [Value], fallback: Value) -> Value {
        choices.contains(value) ? value : fallback
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
        case windowPadding
        case windowBackground
        case overlayCorner
        case overlayAutoCloseSeconds
        case overlaySpeed
        case quickAccessLayout
        case quickAccessSize
        case quickAccessAspectRatio
        case quickAccessMaxVisible
        case showsToasts
        case toastPosition
        case toastSeconds
        case toastPreviewLines
        case plainTextApp
        case keepsOCRLineBreaks
        case textHistoryLimit
        case thumbnailMemoryMB
        case keepsClipboardHistory
        case clipboardRetention
        case clipboardExcludedApps
        case imageFormat
        case downscalesRetina
        case imageQuality
        case stripsMetadata
        case stripsVideoMetadata
        case saveFolderPath
        case saveFolderPaths
        case filenameTemplate
        case videoCodec
        case framesPerSecond
        case recordsSystemAudio
        case recordsMicrophone
        case showsClicks
        case indexesLibraryContent
        case hidesNoticesWhileRecording
        case videoColor
        case videoQuality
        case videoEncoder
        case captureQueueDepth
        case cursorBlurEnabled
        case cursorBlurMode
        case cursorBlurAmount
        case replayFramesPerSecond
        case replayUsesFullResolution
        case replayQuality
        case showsRecordingTimeInMenuBar
        case recordingCountdownSeconds
        case replayBufferEnabled
        case replayBufferSeconds
        case replayDiskLimitGB
        case saveLastDurations
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
        static let windowPadding = 0
        static let windowBackground = WindowBackground.transparent
        static let overlayCorner = OverlayCorner.bottomLeft
        static let overlayAutoCloseSeconds = 0
        static let overlaySpeed = OverlaySpeed.normal
        static let quickAccessLayout = QuickAccessLayout.stack
        static let quickAccessSize = QuickAccessSize.medium
        static let quickAccessAspectRatio = QuickAccessAspectRatio.threeTwo
        static let quickAccessMaxVisible = 5
        static let showsToasts = true
        static let toastPosition = ToastPosition.topCenter
        static let toastPreviewLines = 2
        static let plainTextApp = PlainTextApp.textEdit
        static let keepsOCRLineBreaks = true
        static let textHistoryLimit = 50
        static let thumbnailMemoryMB = 64
        static let keepsClipboardHistory = true
        static let clipboardRetention = ClipboardRetention.forever
        /// Password managers and wallets. Most also mark what they copy as private, which is
        /// always skipped; this catches the ones that don't.
        static let clipboardExcludedApps = [
            "com.apple.Passwords",
            "com.apple.keychainaccess",
        ]
        /// Earlier versions listed these by default. They're removed once, so only apps the
        /// person added stay alongside Apple's two.
        static let formerDefaultExcludedApps: Set<String> = [
            "com.1password.1password",
            "com.agilebits.onepassword7",
            "com.bitwarden.desktop",
            "io.trezor.TrezorSuite",
            "com.ledger.live",
        ]
        static let imageFormat = ImageFormat.png
        static let downscalesRetina = false
        static let imageQuality = 0.85
        static let stripsMetadata = true
        static let stripsVideoMetadata = true
        static let filenameTemplate = "Retrace {date} at {time}"
        static let videoCodec = VideoCodec.hevc
        static let framesPerSecond = 60
        static let recordsSystemAudio = true
        static let recordsMicrophone = false
        static let showsClicks = false
        static let indexesLibraryContent = true
        static let hidesNoticesWhileRecording = true
        static let videoColor = VideoColor.automatic
        static let videoQuality = VideoQuality.original
        static let videoEncoder = VideoEncoderChoice.automatic
        static let captureQueueDepth = 6
        static let cursorBlurEnabled = false
        static let cursorBlurMode = CursorBlurMode.quality
        static let cursorBlurAmount = 0.5
        static let replayFramesPerSecond = 30
        static let replayUsesFullResolution = false
        static let replayQuality = VideoQuality.balanced
        static let showsRecordingTimeInMenuBar = true
        static let recordingCountdownSeconds = 3
        static let replayBufferEnabled = false
        static let replayBufferSeconds = 60
        static let replayDiskLimitGB = 4
        static let saveLastDurations = [15, 20, 25, 30, 60]

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
            return pictures.appendingPathComponent("Retrace", isDirectory: true).path
        }
    }

    static func standardizedSaveFolderPath(_ path: String) -> String {
        guard !path.isEmpty else { return Defaults.saveFolderPath }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
    }

    static func cleanedSaveFolderPaths(_ paths: [String], including defaultPath: String) -> [String] {
        let defaultPath = standardizedSaveFolderPath(defaultPath)
        var result: [String] = []
        var seen = Set<String>()
        for path in paths {
            let normalized = standardizedSaveFolderPath(path)
            if seen.insert(normalized).inserted {
                result.append(normalized)
            }
        }
        if seen.insert(defaultPath).inserted {
            result.insert(defaultPath, at: 0)
        }
        return result
    }
}
