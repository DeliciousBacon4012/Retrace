import AVFoundation
import AppKit
import Observation
import OSLog

/// Runs a screen recording from start to finish: permission, picking what to record,
/// the on-screen controls while recording, and what happens to the finished movie.
@Observable
final class RecordingCoordinator {
    let recorder = ScreenRecorder()

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let permissions: any PermissionProviding
    @ObservationIgnored private let replay: ReplayCoordinator
    @ObservationIgnored private let storage: any CaptureStoring
    @ObservationIgnored private let clipboard: any ClipboardWriting
    @ObservationIgnored private let quickAccess: QuickAccessController
    @ObservationIgnored private let toasts: CaptureToastController
    @ObservationIgnored private let overlay = SelectionOverlay()
    @ObservationIgnored private let hud = RecordingHUDController()
    @ObservationIgnored private let statusItem = RecordingStatusItem()
    @ObservationIgnored private var countdownTask: Task<Bool, Never>?
    @ObservationIgnored private var statusItemAction: StatusItemAction?

    private enum StatusItemAction {
        case cancelCountdown
        case stopRecording
        case stopReplayBuffer
    }

    /// Seconds left before a recording starts, while its countdown runs.
    private(set) var countdown: Int?

    init(
        settings: SettingsStore,
        permissions: any PermissionProviding,
        replay: ReplayCoordinator,
        storage: any CaptureStoring,
        clipboard: any ClipboardWriting,
        quickAccess: QuickAccessController,
        toasts: CaptureToastController
    ) {
        self.settings = settings
        self.permissions = permissions
        self.replay = replay
        self.storage = storage
        self.clipboard = clipboard
        self.quickAccess = quickAccess
        self.toasts = toasts
        recorder.onRecordingBegan = { [weak self] in
            self?.cursorTracker?.start()
        }
        recorder.onFinish = { [weak self] result in
            self?.finish(result)
        }
        hud.onStop = { [weak self] in
            self?.recorder.stop()
        }
        statusItem.onClick = { [weak self] in
            guard let self else { return }
            switch statusItemAction {
            case .cancelCountdown:
                cancelCountdown()
            case .stopRecording:
                recorder.stop()
            case .stopReplayBuffer:
                replay.setEnabled(false)
            case nil:
                break
            }
        }
        followRecorderState()
    }

    /// Shows the active countdown or recording source in the menu bar, then removes it when idle.
    private func followRecorderState() {
        let (state, remaining, showsTime, replayStartedAt, replayLimit) = withObservationTracking {
            (
                recorder.state,
                countdown,
                settings.showsRecordingTimeInMenuBar,
                replay.buffer.startedAt,
                settings.replayBufferSeconds
            )
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.followRecorderState()
            }
        }
        if let remaining {
            statusItemAction = .cancelCountdown
            statusItem.showCountdown(remaining)
        } else if case .recording(let since) = state {
            if showsTime {
                statusItemAction = .stopRecording
                statusItem.showElapsed(
                    since: since,
                    toolTip: String(localized: "Stop Recording"),
                    accessibilityLabel: String(localized: "Stop Recording")
                )
            } else {
                statusItemAction = nil
                statusItem.hide()
            }
        } else if let replayStartedAt {
            statusItemAction = .stopReplayBuffer
            statusItem.showElapsed(
                since: replayStartedAt,
                maximumDuration: replayLimit,
                toolTip: String(localized: "Turn Off Replay Buffer"),
                accessibilityLabel: String(localized: "Replay Buffer")
            )
        } else {
            statusItemAction = nil
            statusItem.hide()
        }
    }

    var isRecording: Bool { recorder.isActive }

    /// True from the moment a recording is asked for until it starts or is called off, so a
    /// second press of the shortcut meanwhile can't open a second picker or overlay.
    @ObservationIgnored private var isPreparing = false
    /// Set while a finished movie gets its second pass. The HUD still shows, so nothing new starts.
    @ObservationIgnored private var isFinishing = false
    /// Follows the pointer when the movie's cursor will be drawn afterward.
    @ObservationIgnored private var cursorTracker: CursorTracker?
    @ObservationIgnored private var finishCodec = VideoCodec.hevc

    /// Starts a recording, or stops the one in progress. During the countdown, cancels it.
    func toggle(_ mode: CaptureMode, savingTo folder: URL? = nil) async {
        if countdown != nil {
            cancelCountdown()
            return
        }
        if recorder.isActive {
            recorder.stop()
            return
        }
        guard !isPreparing, !isFinishing else { return }
        var allowed = permissions.screenRecordingStatus == .granted
        if !allowed { allowed = await permissions.confirmScreenRecordingAccess() == .granted }
        guard allowed else {
            toasts.showScreenRecordingNeeded(then: String(localized: "Try again."))
            return
        }
        isPreparing = true
        defer { isPreparing = false }
        if settings.recordsMicrophone, await !microphoneAllowed() {
            ErrorPresenter.present(String(localized: "Retrace can't use the microphone."), recovery: String(localized: "Allow it in System Settings › Privacy & Security › Microphone, or turn off microphone audio in Settings › Recording."))
            return
        }

        guard let picked = await pickTarget(mode) else { return }
        let (target, screen, area) = picked
        guard await runCountdown(settings.recordingCountdownSeconds) else { return }
        do {
            let url = try await storage.reserveURL(template: settings.filenameTemplate, date: .now, fileExtension: "mov", in: folder ?? settings.saveFolderURL)
            let scale = settings.downscalesRetina ? 1 : (screen?.backingScaleFactor ?? 2)
            // A window can move, so its cursor can't be placed afterward; it keeps the live one.
            let trackedArea: CGRect? = if settings.cursorBlurEnabled, case .display = target { area ?? screen?.frame } else { nil }
            cursorTracker = trackedArea.map { CursorTracker(area: $0, pixelsPerPoint: scale) }
            finishCodec = settings.videoCodec
            let options = RecordingOptions(
                codec: settings.videoCodec,
                framesPerSecond: settings.framesPerSecond,
                showsCursor: cursorTracker == nil,
                recordsSystemAudio: settings.recordsSystemAudio,
                recordsMicrophone: settings.recordsMicrophone,
                scale: scale,
                color: settings.videoColor,
                queueDepth: settings.captureQueueDepth,
                showsClicks: settings.showsClicks
            )
            try await recorder.start(target, options: options, to: url)
            if settings.playsSounds { CaptureSound.play() }
            hud.show(recorder: recorder, on: screen, framing: area)
        } catch is CancellationError {
            // A stop request during recorder startup is an expected cancellation, not an error.
            return
        } catch {
            Log.capture.error("Recording couldn't start: \(error.localizedDescription, privacy: .public)")
            ErrorPresenter.present(error)
        }
    }

    func cancelCountdown() {
        countdownTask?.cancel()
    }

    /// Counts down a second at a time. Returns false if it was cancelled.
    private func runCountdown(_ seconds: Int) async -> Bool {
        guard seconds > 0 else { return true }
        let task = Task { [weak self] () -> Bool in
            for remaining in stride(from: seconds, to: 0, by: -1) {
                self?.countdown = remaining
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return false
                }
            }
            return true
        }
        countdownTask = task
        let finished = await task.value
        countdownTask = nil
        countdown = nil
        return finished
    }

    /// Returns what to record, the screen it's on, and the area to outline (for area recordings).
    private func pickTarget(_ mode: CaptureMode) async -> (RecordingTarget, NSScreen?, CGRect?)? {
        switch mode {
        case .screen:
            guard let screen = NSScreen.underPointer, let displayID = screen.displayID else { return nil }
            return (.display(displayID, rect: nil), screen, nil)
        case .area:
            guard case .area(let rect, let screen)? = await overlay.select(.area),
                  let displayID = screen.displayID
            else { return nil }
            return (.display(displayID, rect: screen.topLeftRelativeRect(for: rect)), screen, rect)
        case .window:
            guard case .window(let window)? = await overlay.select(.window(WindowList.onScreenWindows())) else { return nil }
            let screen = NSScreen.screens.first { $0.frame.intersects(window.frame) } ?? NSScreen.main
            return (.window(window.id), screen, nil)
        }
    }

    private func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        default: false
        }
    }

    private func finish(_ result: Result<URL, any Error>) {
        let cursor = cursorTracker?.stop()
        cursorTracker = nil
        switch result {
        case .success(let url):
            if settings.playsSounds { CaptureSound.play() }
            let finishing = RecordingFinisher.Options(
                codec: finishCodec,
                quality: settings.videoQuality,
                encoder: settings.videoEncoder,
                cursor: cursor,
                cursorBlurMode: settings.cursorBlurMode,
                cursorBlurAmount: settings.cursorBlurAmount
            )
            isFinishing = true
            Task {
                // The HUD keeps saying "Saving…" until this is done.
                defer {
                    isFinishing = false
                    hud.hide()
                }
                do {
                    try await RecordingFinisher.process(url, options: finishing)
                } catch {
                    Log.capture.error("Couldn't process a recording: \(error.localizedDescription, privacy: .public)")
                    ErrorPresenter.present(error, recovery: String(localized: "The recording was kept as it was captured."))
                }
                // Clean the file before it's copied or shown, so nothing hands out the original.
                if settings.stripsVideoMetadata {
                    do {
                        try await VideoMetadata.removeAll(from: url)
                    } catch {
                        Log.capture.error("Couldn't secure a recording's metadata: \(error.localizedDescription, privacy: .public)")
                        ErrorPresenter.present(error, recovery: String(localized: "The recording remains in its save folder. Retrace did not copy it or open it in Quick Access. Review the file before sharing."))
                        return
                    }
                }
                if settings.copiesToClipboard { clipboard.copyFile(at: url) }
                guard settings.showsQuickAccess else {
                    toasts.show(.init(kind: .recordingSaved, symbolName: "record.circle", title: String(localized: "Recording saved"), detail: url.lastPathComponent, actions: .forMovie(at: url, clipboard: clipboard)))
                    return
                }
                guard let poster = await Self.posterFrame(for: url) else {
                    Log.capture.error("Recording was saved, but its preview frame couldn't be created")
                    toasts.show(.init(
                        kind: .recordingSaved,
                        symbolName: "record.circle",
                        title: String(localized: "Recording saved"),
                        detail: url.lastPathComponent,
                        actions: .forMovie(at: url, clipboard: clipboard)
                    ))
                    return
                }
                var capture = CapturedImage(image: poster, scale: 2, date: .now)
                capture.fileURL = url
                capture.isVideo = true
                quickAccess.show(capture)
            }
        case .failure(let error):
            hud.hide()
            ErrorPresenter.present(error)
        }
    }

    private static func posterFrame(for url: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1200, height: 1200)
        return try? await generator.image(at: .zero).image
    }
}
