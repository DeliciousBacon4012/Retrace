import AVFoundation
import AppKit
import Observation
import OSLog

/// Turns the replay buffer on and off from Settings, and saves clips from it.
@Observable
final class ReplayCoordinator {
    let buffer = ReplayBuffer()

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let permissions: any PermissionProviding
    @ObservationIgnored private let storage: any CaptureStoring
    @ObservationIgnored private let clipboard: any ClipboardWriting
    @ObservationIgnored private let quickAccess: QuickAccessController
    @ObservationIgnored private let toasts: CaptureToastController

    init(settings: SettingsStore, permissions: any PermissionProviding, storage: any CaptureStoring, clipboard: any ClipboardWriting, quickAccess: QuickAccessController, toasts: CaptureToastController) {
        self.settings = settings
        self.permissions = permissions
        self.storage = storage
        self.clipboard = clipboard
        self.quickAccess = quickAccess
        self.toasts = toasts
    }

    /// Starts the buffer at launch if it was on last time and access is still allowed.
    func start() {
        follow()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled, permissions.screenRecordingStatus != .granted else {
            settings.replayBufferEnabled = enabled
            return
        }
        Task {
            guard await permissions.confirmScreenRecordingAccess() == .granted else {
                toasts.showScreenRecordingNeeded(then: String(localized: "Turn the replay buffer on again."))
                return
            }
            settings.replayBufferEnabled = true
        }
    }

    func toggle() {
        setEnabled(!settings.replayBufferEnabled)
    }

    /// Saves the length chosen in Settings, or the whole buffer.
    func saveDefaultLength() async {
        let seconds = settings.defaultReplaySeconds
        await saveClip(lastSeconds: seconds > 0 ? seconds : nil)
    }

    /// While a full recording runs, the buffer pauses, so the two don't both encode the screen.
    /// It starts over afterward if it's still turned on.
    var isSuspendedForRecording = false

    /// Saves the buffered clip to the save folder and shows it in Quick Access: all of it,
    /// or with `lastSeconds`, just that much from the end.
    func saveClip(lastSeconds: Int? = nil, to folder: URL? = nil) async {
        guard buffer.isOn else {
            ErrorPresenter.present(ReplayError.notRunning, recovery: String(localized: "Turn it on in the Record menu or the menu bar, then save a replay any time."))
            return
        }
        do {
            let url = try await storage.reserveURL(template: settings.filenameTemplate + " Replay", date: .now, fileExtension: "mov", in: folder ?? settings.saveFolderURL)
            let saved = try await buffer.save(to: url, lastSeconds: lastSeconds.map(Double.init))
            if settings.stripsVideoMetadata {
                do {
                    try await VideoMetadata.removeAll(from: url)
                } catch {
                    Log.capture.error("Couldn't secure a replay's metadata: \(error.localizedDescription, privacy: .public)")
                    ErrorPresenter.present(error, recovery: String(localized: "The replay remains in its save folder. Retrace did not copy it or open it in Quick Access. Review the file before sharing."))
                    return
                }
            }
            if settings.playsSounds { CaptureSound.play() }
            Log.capture.info("Saved a replay")
            if let lastSeconds, saved < Double(lastSeconds) - 0.5 {
                // Less was buffered than asked for, so say how much the clip holds.
                let length = Duration.seconds(Int(saved.rounded())).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
                toasts.show(.init(kind: .recordingSaved, symbolName: "gobackward", title: String(localized: "Saved \(length)"), detail: String(localized: "That's all the replay buffer held so far."), actions: .forMovie(at: url, clipboard: clipboard)))
            } else if !settings.showsQuickAccess {
                toasts.show(.init(kind: .recordingSaved, symbolName: "gobackward", title: String(localized: "Replay saved"), detail: url.lastPathComponent, actions: .forMovie(at: url, clipboard: clipboard)))
            }
            guard settings.showsQuickAccess else { return }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1200, height: 1200)
            if let poster = try? await generator.image(at: .zero).image {
                var capture = CapturedImage(image: poster, scale: 2, date: .now)
                capture.fileURL = url
                capture.isVideo = true
                quickAccess.show(capture)
            } else {
                Log.capture.error("Replay was saved, but its preview frame couldn't be created")
                toasts.show(.init(
                    kind: .recordingSaved,
                    symbolName: "gobackward",
                    title: String(localized: "Replay saved"),
                    detail: url.lastPathComponent,
                    actions: .forMovie(at: url, clipboard: clipboard)
                ))
            }
        } catch {
            Log.capture.error("Saving a replay failed: \(error.localizedDescription, privacy: .public)")
            ErrorPresenter.present(error)
        }
    }

    /// Restarts the buffer whenever a setting it depends on changes.
    private func follow() {
        let wanted = withObservationTracking {
            (
                enabled: settings.replayBufferEnabled,
                seconds: settings.replayBufferSeconds,
                limit: settings.replayDiskLimitGB,
                suspended: isSuspendedForRecording,
                fps: settings.replayFramesPerSecond,
                codec: settings.videoCodec,
                audio: settings.recordsSystemAudio,
                quality: settings.replayQuality,
                encoder: settings.videoEncoder,
                fullResolution: settings.replayUsesFullResolution,
                color: settings.videoColor,
                queueDepth: settings.captureQueueDepth,
                showsOwnWindows: settings.showsRetraceInRecordings
            )
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.follow()
            }
        }

        buffer.stop()
        guard wanted.enabled, !wanted.suspended, permissions.screenRecordingStatus == .granted else { return }
        Task {
            do {
                try await buffer.start(
                    seconds: wanted.seconds,
                    sizeLimitGB: wanted.limit,
                    framesPerSecond: wanted.fps,
                    codec: wanted.codec,
                    quality: wanted.quality,
                    encoder: wanted.encoder,
                    usesFullResolution: wanted.fullResolution,
                    color: wanted.color,
                    queueDepth: wanted.queueDepth,
                    showsOwnWindows: wanted.showsOwnWindows,
                    includesAudio: wanted.audio
                )
            } catch is CancellationError {
                // A setting change or stop invalidated this startup; the newer state owns recovery.
                return
            } catch {
                Log.capture.error("Replay buffer couldn't start: \(error.localizedDescription, privacy: .public)")
                settings.replayBufferEnabled = false
                ErrorPresenter.present(error)
            }
        }
    }
}
