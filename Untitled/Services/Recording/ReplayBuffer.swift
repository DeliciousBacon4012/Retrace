import AVFoundation
import AppKit
import Observation
import OSLog
import ScreenCaptureKit

/// Prevents a startup task from publishing a stream after the buffer was stopped or restarted.
nonisolated struct ReplayBufferGeneration: Sendable {
    private(set) var value = 0

    mutating func begin() -> Int {
        value &+= 1
        return value
    }

    mutating func invalidate() {
        value &+= 1
    }

    func accepts(_ token: Int) -> Bool {
        token == value
    }
}

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
    @ObservationIgnored private var generation = ReplayBufferGeneration()

    var isOn: Bool {
        switch state {
        case .off: false
        default: true
        }
    }

    func start(seconds: Int, sizeLimitGB: Int, framesPerSecond: Int, codec: VideoCodec, includesAudio: Bool) async throws {
        guard state == .off else { return }
        let token = generation.begin()
        guard CGPreflightScreenCaptureAccess() else { throw CaptureError.permissionDenied }
        state = .starting
        var pendingStream: SCStream?
        var pendingWriter: ReplayWriter?
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            try checkStartIsCurrent(token)
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
            pendingWriter = writer
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            pendingStream = stream
            try stream.addStreamOutput(writer, type: .screen, sampleHandlerQueue: writer.sampleQueue)
            if includesAudio {
                try stream.addStreamOutput(writer, type: .audio, sampleHandlerQueue: writer.sampleQueue)
            }
            try checkStartIsCurrent(token)
            self.stream = stream
            self.writer = writer
            try await stream.startCapture()
            try checkStartIsCurrent(token)
            state = .running(since: .now)
            Log.capture.info("Replay buffer started")
        } catch {
            if generation.accepts(token) {
                generation.invalidate()
                if let pendingStream, self.stream === pendingStream {
                    self.stream = nil
                    self.writer = nil
                }
                state = .off
            }
            if let pendingStream {
                try? await pendingStream.stopCapture()
            }
            pendingWriter?.shutDown()
            throw error
        }
    }

    func stop() {
        generation.invalidate()
        let stream = self.stream
        let writer = self.writer
        self.stream = nil
        self.writer = nil
        state = .off
        guard let stream else {
            writer?.shutDown()
            return
        }
        Task {
            try? await stream.stopCapture()
            writer?.shutDown()
        }
        Log.capture.info("Replay buffer stopped")
    }

    private func checkStartIsCurrent(_ token: Int) throws {
        guard generation.accepts(token), state == .starting else {
            throw CancellationError()
        }
    }

    /// Saves what's buffered to `url` as a normal movie that starts at zero: everything, or
    /// with `lastSeconds`, exactly that much from the end, if that much has been buffered.
    /// Returns the length saved, in seconds.
    @discardableResult
    func save(to url: URL, lastSeconds: Double? = nil) async throws -> Double {
        guard case .running(let since) = state, let writer else { throw ReplayError.notRunning }
        // The clip ends exactly at this moment, on the clock the screen's frames use.
        let requested = CMClockGetTime(CMClockGetHostTimeClock())
        state = .saving
        defer {
            if self.writer != nil { state = .running(since: since) }
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("replay-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let overhang = try await Task.detached(priority: .userInitiated) {
            // The newest second is still being encoded; wait for it so nothing is cut off.
            await writer.waitUntilBuffered(through: requested)
            return try writer.writeSnapshot(to: temporary, lastSeconds: lastSeconds, endingAt: requested)
        }.value
        return try await Self.export(temporary, to: url, lastSeconds: lastSeconds, trimmingEnd: overhang)
    }

    /// Rewrites the fragmented snapshot into a regular movie whose timeline starts at zero,
    /// ending `trimmingEnd` seconds before the snapshot does (the moment the save was asked
    /// for) and keeping only the last `lastSeconds` when given. The cut can fall between
    /// keyframes: the movie's edit list starts playback exactly there without re-encoding.
    private static func export(_ source: URL, to destination: URL, lastSeconds: Double?, trimmingEnd: Double) async throws -> Double {
        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .video) + asset.loadTracks(withMediaType: .audio)
        var ranges: [CMTimeRange] = []
        for track in tracks {
            ranges.append(try await track.load(.timeRange))
        }
        guard let first = ranges.first else { throw ReplayError.empty }
        let earliest = ranges.dropFirst().reduce(first.start) { CMTimeMinimum($0, $1.start) }
        let latest = ranges.dropFirst().reduce(first.end) { CMTimeMaximum($0, $1.end) }
        let end = CMTimeMaximum(earliest, CMTimeSubtract(latest, CMTime(seconds: trimmingEnd, preferredTimescale: 600)))
        var start = earliest
        if let lastSeconds {
            start = CMTimeMaximum(earliest, CMTimeSubtract(end, CMTime(seconds: lastSeconds, preferredTimescale: 600)))
        }
        let window = CMTimeRange(start: start, end: end)

        let composition = AVMutableComposition()
        for (track, range) in zip(tracks, ranges) {
            let kept = range.intersection(window)
            guard kept.duration.seconds > 0,
                  let compositionTrack = composition.addMutableTrack(withMediaType: track.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            try compositionTrack.insertTimeRange(kept, of: track, at: CMTimeSubtract(kept.start, start))
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw ReplayError.empty
        }
        try await session.export(to: destination, as: .mov)
        return window.duration.seconds
    }
}

extension ReplayBuffer: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let stoppedID = ObjectIdentifier(stream)
        Task { @MainActor [weak self] in
            guard let self, self.stream.map(ObjectIdentifier.init) == stoppedID else { return }
            Log.capture.info("Replay stream stopped by the system: \(error.localizedDescription, privacy: .public)")
            self.stop()
        }
    }
}
