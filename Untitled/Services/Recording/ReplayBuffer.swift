import AVFoundation
import AppKit
import Observation
import OSLog
import ScreenCaptureKit

/// Keeps the last stretch of screen activity ready to save, like a game console's replay.
/// Runs at the display's point resolution to stay light on CPU, memory, and disk.
@Observable
final class ReplayBuffer: NSObject {
    enum State: Equatable {
        case off
        case starting
        case running(since: Date)
        case saving
    }

    private(set) var state: State = .off

    @ObservationIgnored private var stream: SCStream?
    @ObservationIgnored private var writer: ReplayWriter?

    var isOn: Bool {
        switch state {
        case .off: false
        default: true
        }
    }

    func start(seconds: Int, sizeLimitGB: Int, framesPerSecond: Int, codec: VideoCodec, includesAudio: Bool) async throws {
        guard state == .off else { return }
        guard CGPreflightScreenCaptureAccess() else { throw CaptureError.permissionDenied }
        state = .starting
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let displayID = NSScreen.underPointer?.displayID
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
                throw CaptureError.displayNotFound
            }
            let ownProcess = ProcessInfo.processInfo.processIdentifier
            let ownApps = content.applications.filter { $0.processID == ownProcess }
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

            let width = display.width / 2 * 2
            let height = display.height / 2 * 2
            let configuration = SCStreamConfiguration()
            configuration.width = width
            configuration.height = height
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(framesPerSecond, 1)))
            configuration.showsCursor = true
            configuration.queueDepth = 6
            configuration.capturesAudio = includesAudio
            configuration.excludesCurrentProcessAudio = true

            let writer = try ReplayWriter(configuration: .init(
                width: width,
                height: height,
                framesPerSecond: framesPerSecond,
                codec: codec,
                includesAudio: includesAudio,
                maximumSeconds: Double(seconds),
                maximumBytes: sizeLimitGB * 1_000_000_000
            ))
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(writer, type: .screen, sampleHandlerQueue: writer.sampleQueue)
            if includesAudio {
                try stream.addStreamOutput(writer, type: .audio, sampleHandlerQueue: writer.sampleQueue)
            }
            try await stream.startCapture()
            self.stream = stream
            self.writer = writer
            state = .running(since: .now)
            Log.capture.info("Replay buffer started")
        } catch {
            state = .off
            throw error
        }
    }

    func stop() {
        guard let stream else {
            state = .off
            return
        }
        let writer = writer
        self.stream = nil
        self.writer = nil
        state = .off
        Task {
            try? await stream.stopCapture()
            writer?.shutDown()
        }
        Log.capture.info("Replay buffer stopped")
    }

    /// Saves what's buffered to `url` as a normal movie that starts at zero.
    func save(to url: URL) async throws {
        guard case .running(let since) = state, let writer else { throw ReplayError.notRunning }
        state = .saving
        defer {
            if self.writer != nil { state = .running(since: since) }
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("replay-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try await Task.detached(priority: .userInitiated) {
            try writer.writeSnapshot(to: temporary)
        }.value
        try await Self.export(temporary, to: url)
    }

    /// Rewrites the fragmented snapshot into a regular movie whose timeline starts at zero.
    private static func export(_ source: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        let composition = AVMutableComposition()
        for track in try await asset.loadTracks(withMediaType: .video) + asset.loadTracks(withMediaType: .audio) {
            let range = try await track.load(.timeRange)
            let mediaType = track.mediaType
            guard range.duration.seconds > 0,
                  let compositionTrack = composition.addMutableTrack(withMediaType: mediaType, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            try compositionTrack.insertTimeRange(range, of: track, at: .zero)
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw ReplayError.empty
        }
        try await session.export(to: destination, as: .mov)
    }
}

extension ReplayBuffer: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor in
            Log.capture.info("Replay stream stopped by the system: \(error.localizedDescription, privacy: .public)")
            self.stop()
        }
    }
}
