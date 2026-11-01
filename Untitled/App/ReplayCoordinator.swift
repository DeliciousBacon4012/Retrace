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
    @ObservationIgnored private let quickAccess: QuickAccessController

    init(settings: SettingsStore, permissions: any PermissionProviding, storage: any CaptureStoring, quickAccess: QuickAccessController) {
        self.settings = settings
        self.permissions = permissions
        self.storage = storage
        self.quickAccess = quickAccess
    }

    /// Starts the buffer at launch if it was on last time and access is still allowed.
    func start() {
        follow()
    }

    func setEnabled(_ enabled: Bool) {
        if enabled, permissions.screenRecordingStatus != .granted {
            permissions.requestScreenRecordingAccess()
            ErrorPresenter.present(CaptureError.permissionDenied, recovery: String(localized: "Turn on Untitled in System Settings › Privacy & Security › Screen & System Audio Recording, then turn the replay buffer on again."))
            return
        }
        settings.replayBufferEnabled = enabled
    }

    /// Saves the buffered clip to the save folder and shows it in Quick Access.
    func saveClip() async {
        guard buffer.isOn else {
            ErrorPresenter.present(ReplayError.notRunning, recovery: String(localized: "Turn it on from the Capture page or the menu bar, then save a replay any time."))
            return
        }
        do {
            let url = try storage.reserveURL(template: settings.filenameTemplate + " Replay", date: .now, fileExtension: "mov", in: settings.saveFolderURL)
            try await buffer.save(to: url)
            if settings.stripsVideoMetadata { await VideoMetadata.removeAll(from: url) }
            if settings.playsSounds { CaptureSound.play() }
            Log.capture.info("Saved a replay")
            guard settings.showsQuickAccess else { return }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1200, height: 1200)
            if let poster = try? await generator.image(at: .zero).image {
                var capture = CapturedImage(image: poster, scale: 2, date: .now)
                capture.fileURL = url
                capture.isVideo = true
                quickAccess.show(capture)
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
                fps: settings.framesPerSecond,
                codec: settings.videoCodec,
                audio: settings.recordsSystemAudio
            )
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.follow()
            }
        }

        buffer.stop()
        guard wanted.enabled, permissions.screenRecordingStatus == .granted else { return }
        Task {
            do {
                try await buffer.start(
                    seconds: wanted.seconds,
                    sizeLimitGB: wanted.limit,
                    framesPerSecond: min(wanted.fps, 30),
                    codec: wanted.codec,
                    includesAudio: wanted.audio
                )
            } catch {
                Log.capture.error("Replay buffer couldn't start: \(error.localizedDescription, privacy: .public)")
                settings.replayBufferEnabled = false
                ErrorPresenter.present(error)
            }
        }
    }
}
