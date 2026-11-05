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
    @ObservationIgnored private let displayPicker = DisplayPicker()
    @ObservationIgnored private let hud = RecordingHUDController()
    @ObservationIgnored private let statusItem = RecordingStatusItem()
    @ObservationIgnored private var countdownTask: Task<Bool, Never>?
    /// What the running recording shows, for the menu bar item's menu.
    @ObservationIgnored private var recordingDescription: String?
    /// Set when the countdown should end early and the recording start right away.
    @ObservationIgnored private var startsNow = false

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
        recorder.onRecordingBegan = { [weak self] uptime in
            self?.cursorTracker?.movieBegan(atUptime: uptime)
        }
        recorder.onFinish = { [weak self] result in
            self?.finish(result)
        }
        hud.onStop = { [weak self] in
            self?.recorder.stop()
        }
        statusItem.buildMenu = { [weak self] menu in
            self?.fillStatusMenu(menu)
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
            statusItem.showCountdown(remaining)
        } else if case .recording(let since) = state {
            if showsTime {
                statusItem.showElapsed(
                    since: since,
                    toolTip: String(localized: "Recording Options"),
                    accessibilityLabel: String(localized: "Recording")
                )
            } else {
                statusItem.hide()
            }
        } else if let replayStartedAt {
            statusItem.showElapsed(
                since: replayStartedAt,
                maximumDuration: replayLimit,
                toolTip: String(localized: "Replay Buffer Options"),
                accessibilityLabel: String(localized: "Replay Buffer")
            )
        } else {
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

    /// Set when the running recording should be thrown away instead of saved.
    @ObservationIgnored private var discardsWhenStopped = false

    /// The shortcut pair for full-screen recording: the first press starts one, a second press
    /// throws it away. The movie goes to the Trash, so a mistaken press can still be undone.
    func startOrDiscardScreenRecording() async {
        if countdown != nil {
            cancelCountdown()
            return
        }
        if recorder.isActive {
            discardsWhenStopped = true
            recorder.stop()
            return
        }
        await toggle(.screen)
    }

    /// Stops the running recording and saves it. Does nothing when nothing is recording.
    func stopAndSave() {
        guard recorder.isActive else { return }
        discardsWhenStopped = false
        recorder.stop()
    }

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
        // A second press while choosing a display backs out, as Escape does.
        if displayPicker.isPicking {
            displayPicker.cancel()
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
        recordingDescription = switch mode {
        case .screen: screen.map { String(localized: "Recording \($0.localizedName)") } ?? String(localized: "Recording the screen")
        case .area: area.map { String(localized: "Recording an area, \(Int($0.width)) × \(Int($0.height))") } ?? String(localized: "Recording an area")
        case .window: String(localized: "Recording a window")
        }
        guard await runCountdown(settings.recordingCountdownSeconds) else { return }
        do {
            let url = try await storage.reserveURL(template: settings.filenameTemplate, date: .now, fileExtension: "mov", in: folder ?? settings.saveFolderURL)
            let scale = settings.downscalesRetina ? 1 : (screen?.backingScaleFactor ?? 2)
            // A window can move, so its cursor can't be placed afterward; it keeps the live one.
            let trackedArea: CGRect? = if settings.cursorBlurEnabled, case .display = target { area ?? screen?.frame } else { nil }
            cursorTracker = trackedArea.map { CursorTracker(area: $0, pixelsPerPoint: scale) }
            finishCodec = settings.videoCodec
            var options = RecordingOptions(
                codec: settings.videoCodec,
                framesPerSecond: settings.framesPerSecond,
                showsCursor: cursorTracker == nil,
                recordsSystemAudio: settings.recordsSystemAudio,
                recordsMicrophone: settings.recordsMicrophone,
                scale: scale,
                color: settings.videoColor,
                queueDepth: settings.captureQueueDepth,
                showsClicks: settings.showsClicks,
                showsOwnWindows: settings.showsRetraceInRecordings
            )
            // The controls go up first, so the recording knows which windows to leave out.
            hud.show(recorder: recorder, on: screen, framing: area)
            options.hiddenWindowIDs = hud.windowIDs
            // The buffer steps aside for the recording and starts over once it's saved.
            replay.isSuspendedForRecording = true
            // The pointer is followed from before the first frame, then lined up with it.
            cursorTracker?.start()
            try await recorder.start(target, options: options, to: url)
            if settings.playsSounds { CaptureSound.play() }
        } catch is CancellationError {
            // A stop request during recorder startup is an expected cancellation, not an error.
            _ = cursorTracker?.stop()
            cursorTracker = nil
            hud.hide()
            replay.isSuspendedForRecording = false
            return
        } catch {
            _ = cursorTracker?.stop()
            cursorTracker = nil
            hud.hide()
            replay.isSuspendedForRecording = false
            Log.capture.error("Recording couldn't start: \(error.localizedDescription, privacy: .public)")
            ErrorPresenter.present(error)
        }
    }

    func cancelCountdown() {
        countdownTask?.cancel()
    }

    /// Ends the countdown early and starts recording.
    func startNow() {
        guard countdownTask != nil else { return }
        startsNow = true
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
        let finished = await task.value || startsNow
        startsNow = false
        countdownTask = nil
        countdown = nil
        return finished
    }

    /// Returns what to record, the screen it's on, and the area to outline (for area recordings).
    private func pickTarget(_ mode: CaptureMode) async -> (RecordingTarget, NSScreen?, CGRect?)? {
        switch mode {
        case .screen:
            // With more than one display, the person points at the one they mean.
            let chosen = NSScreen.screens.count > 1 ? await displayPicker.pick() : NSScreen.underPointer
            guard let screen = chosen, let displayID = screen.displayID else { return nil }
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

    // MARK: Menu bar item

    /// The menu under the red dot: what's running, then only the actions that apply to it.
    private func fillStatusMenu(_ menu: NSMenu) {
        let shortcuts = settings.shortcuts
        if let countdown {
            menu.addItem(.sectionHeader(title: String(localized: "Recording starts in \(countdown)")))
            menu.addItem(NSMenuItem.action(String(localized: "Start Now"), systemImage: "record.circle") { [weak self] in
                self?.startNow()
            })
            menu.addItem(NSMenuItem.action(String(localized: "Cancel"), systemImage: "xmark.circle") { [weak self] in
                self?.cancelCountdown()
            })
        } else if case .recording(let since) = recorder.state {
            menu.addItem(.sectionHeader(title: recordingDescription ?? String(localized: "Recording")))
            let elapsed = Duration.seconds(Int(Date.now.timeIntervalSince(since))).formatted(.time(pattern: .minuteSecond))
            menu.addItem(.note(String(localized: "\(elapsed) so far"), systemImage: "clock"))
            menu.addItem(.note(audioDescription, systemImage: settings.recordsMicrophone ? "mic" : "speaker.wave.2"))
            menu.addItem(.separator())
            menu.addItem(NSMenuItem.action(String(localized: "Stop and Save"), systemImage: "stop.circle", shortcut: shortcuts["saveRecording"]) { [weak self] in
                self?.stopAndSave()
            })
            menu.addItem(NSMenuItem.action(String(localized: "Discard Recording"), systemImage: "trash", shortcut: shortcuts["recordScreenOrDiscard"]) { [weak self] in
                guard let self, recorder.isActive else { return }
                discardsWhenStopped = true
                recorder.stop()
            })
        } else if recorder.state == .finishing || isFinishing {
            menu.addItem(.sectionHeader(title: String(localized: "Saving Recording…")))
        } else if replay.buffer.isOn {
            let length = SaveLastMenu.title(for: settings.replayBufferSeconds)
            menu.addItem(.sectionHeader(title: String(localized: "Replay Buffer")))
            menu.addItem(.note(String(localized: "Keeping the last \(length)"), systemImage: "arrow.trianglehead.counterclockwise"))
            menu.addItem(.separator())
            let isSaving = replay.buffer.state == .saving
            for seconds in settings.saveLastDurations {
                let item = NSMenuItem.action(String(localized: "Save Last \(SaveLastMenu.title(for: seconds))"), shortcut: shortcuts[QuickAction.saveLast(seconds).id]) { [weak self] in
                    Task { await self?.replay.saveClip(lastSeconds: seconds) }
                }
                item.isEnabled = !isSaving && seconds <= settings.replayBufferSeconds
                menu.addItem(item)
            }
            let entire = NSMenuItem.action(String(localized: "Save Entire Buffer"), systemImage: "gobackward", shortcut: shortcuts["saveReplay"]) { [weak self] in
                Task { await self?.replay.saveClip() }
            }
            entire.isEnabled = !isSaving
            menu.addItem(entire)
            menu.addItem(.separator())
            menu.addItem(NSMenuItem.action(String(localized: "Turn Off Replay Buffer"), systemImage: "stop.circle", shortcut: shortcuts["toggleReplay"]) { [weak self] in
                self?.replay.setEnabled(false)
            })
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem.action(String(localized: "Recording Settings…"), systemImage: "gearshape") {
            MainWindowRouter.shared.requestSettings(.recording)
        })
    }

    private var audioDescription: String {
        switch (settings.recordsSystemAudio, settings.recordsMicrophone) {
        case (true, true): String(localized: "System audio and microphone")
        case (true, false): String(localized: "System audio, no microphone")
        case (false, true): String(localized: "Microphone, no system audio")
        case (false, false): String(localized: "No audio")
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
        replay.isSuspendedForRecording = false
        if discardsWhenStopped {
            discardsWhenStopped = false
            hud.hide()
            if case .success(let url) = result { discard(url) }
            return
        }
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

    private func discard(_ url: URL) {
        var inTrash: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &inTrash)
        } catch {
            Log.capture.error("Couldn't move a discarded recording to the Trash: \(error.localizedDescription, privacy: .public)")
            return
        }
        let trashed = inTrash as URL?
        toasts.show(.init(
            kind: .recordingSaved,
            symbolName: "trash",
            title: String(localized: "Recording discarded"),
            detail: String(localized: "It's in the Trash if you need it."),
            actions: trashed.map { url in
                [.init(title: String(localized: "Show in Trash"), systemImage: "trash") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }]
            } ?? []
        ))
    }

    private static func posterFrame(for url: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1200, height: 1200)
        return try? await generator.image(at: .zero).image
    }
}
