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
    @ObservationIgnored private let storage: any CaptureStoring
    @ObservationIgnored private let clipboard: any ClipboardWriting
    @ObservationIgnored private let quickAccess: QuickAccessController
    @ObservationIgnored private let toasts: CaptureToastController
    @ObservationIgnored private let overlay = SelectionOverlay()
    @ObservationIgnored private let hud = RecordingHUDController()
    @ObservationIgnored private let statusItem = RecordingStatusItem()
    @ObservationIgnored private var countdownTask: Task<Bool, Never>?

    /// Seconds left before a recording starts, while its countdown runs.
    private(set) var countdown: Int?

    init(
        settings: SettingsStore,
        permissions: any PermissionProviding,
        storage: any CaptureStoring,
        clipboard: any ClipboardWriting,
        quickAccess: QuickAccessController,
        toasts: CaptureToastController
    ) {
        self.settings = settings
        self.permissions = permissions
        self.storage = storage
        self.clipboard = clipboard
        self.quickAccess = quickAccess
        self.toasts = toasts
        recorder.onFinish = { [weak self] result in
            self?.finish(result)
        }
        hud.onStop = { [weak self] in
            self?.recorder.stop()
        }
        statusItem.onClick = { [weak self] in
            guard let self else { return }
            if countdown != nil {
                cancelCountdown()
            } else {
                recorder.stop()
            }
        }
        followRecorderState()
    }

    /// Shows the countdown, then the elapsed time if that's turned on, in the menu bar,
    /// and removes it the moment recording stops, however it was stopped.
    private func followRecorderState() {
        let (state, remaining, showsTime) = withObservationTracking {
            (recorder.state, countdown, settings.showsRecordingTimeInMenuBar)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.followRecorderState()
            }
        }
        if let remaining {
            statusItem.showCountdown(remaining)
        } else if case .recording(let since) = state, showsTime {
            statusItem.showElapsed(since: since)
        } else {
            statusItem.hide()
        }
    }

    var isRecording: Bool { recorder.isActive }

    /// True from the moment a recording is asked for until it starts or is called off, so a
    /// second press of the shortcut meanwhile can't open a second picker or overlay.
    @ObservationIgnored private var isPreparing = false

    /// Starts a recording, or stops the one in progress. During the countdown, cancels it.
    func toggle(_ mode: CaptureMode) async {
        if countdown != nil {
            cancelCountdown()
            return
        }
        if recorder.isActive {
            recorder.stop()
            return
        }
        guard !isPreparing else { return }
        guard permissions.screenRecordingStatus == .granted else {
            toasts.showScreenRecordingNeeded(then: String(localized: "Try again."))
            return
        }
        isPreparing = true
        defer { isPreparing = false }
        if settings.recordsMicrophone, await !microphoneAllowed() {
            ErrorPresenter.present(String(localized: "Untitled can't use the microphone."), recovery: String(localized: "Allow it in System Settings › Privacy & Security › Microphone, or turn off microphone audio in Settings › Recording."))
            return
        }

        guard let picked = await pickTarget(mode) else { return }
        let (target, screen, area) = picked
        guard await runCountdown(settings.recordingCountdownSeconds) else { return }
        do {
            let url = try storage.reserveURL(template: settings.filenameTemplate, date: .now, fileExtension: "mov", in: settings.saveFolderURL)
            let scale = settings.downscalesRetina ? 1 : (screen?.backingScaleFactor ?? 2)
            let options = RecordingOptions(
                codec: settings.videoCodec,
                framesPerSecond: settings.framesPerSecond,
                showsCursor: true,
                recordsSystemAudio: settings.recordsSystemAudio,
                recordsMicrophone: settings.recordsMicrophone,
                scale: scale
            )
            try await recorder.start(target, options: options, to: url)
            if settings.playsSounds { CaptureSound.play() }
            hud.show(recorder: recorder, on: screen, framing: area)
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
        hud.hide()
        switch result {
        case .success(let url):
            if settings.playsSounds { CaptureSound.play() }
            Task {
                // Clean the file before it's copied or shown, so nothing hands out the original.
                if settings.stripsVideoMetadata { await VideoMetadata.removeAll(from: url) }
                if settings.copiesToClipboard { clipboard.copyFile(at: url) }
                guard settings.showsQuickAccess else {
                    toasts.show(.init(kind: .recordingSaved, symbolName: "record.circle", title: String(localized: "Recording saved"), detail: url.lastPathComponent, actions: .forMovie(at: url, clipboard: clipboard)))
                    return
                }
                guard let poster = await Self.posterFrame(for: url) else { return }
                var capture = CapturedImage(image: poster, scale: 2, date: .now)
                capture.fileURL = url
                capture.isVideo = true
                quickAccess.show(capture)
            }
        case .failure(let error):
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
