import AVFoundation
import Observation
import OSLog
import ScreenCaptureKit

/// What to record: a display (or one area of it), or a single window.
nonisolated enum RecordingTarget: Sendable {
    /// `rect` is in points relative to the display's top-left corner; `nil` records all of it.
    case display(CGDirectDisplayID, rect: CGRect?)
    case window(CGWindowID)
}

/// How a recording should be made.
nonisolated struct RecordingOptions: Sendable {
    var codec: VideoCodec
    var framesPerSecond: Int
    var showsCursor: Bool
    var recordsSystemAudio: Bool
    var recordsMicrophone: Bool
    var scale: CGFloat
}

/// Records the screen to a movie file using ScreenCaptureKit's built-in recording output.
@Observable
final class ScreenRecorder: NSObject {
    enum State: Equatable {
        case idle
        case starting
        case recording(since: Date)
        case finishing
    }

    private(set) var state: State = .idle

    /// Called once per recording with the finished file, or the reason it failed.
    @ObservationIgnored var onFinish: ((Result<URL, any Error>) -> Void)?

    @ObservationIgnored private var stream: SCStream?
    @ObservationIgnored private var recordingOutput: SCRecordingOutput?
    @ObservationIgnored private var outputURL: URL?
    /// Identifies the current recording, so late callbacks from an earlier one are ignored.
    @ObservationIgnored private var recordingID: UUID?

    var isActive: Bool { state != .idle }

    func start(_ target: RecordingTarget, options: RecordingOptions, to url: URL) async throws {
        guard state == .idle else { return }
        state = .starting
        do {
            let (filter, configuration) = try await Self.makeStream(for: target, options: options)

            let outputConfiguration = SCRecordingOutputConfiguration()
            outputConfiguration.outputURL = url
            outputConfiguration.outputFileType = .mov
            outputConfiguration.videoCodecType = options.codec == .hevc ? .hevc : .h264
            let output = SCRecordingOutput(configuration: outputConfiguration, delegate: self)

            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addRecordingOutput(output)
            try await stream.startCapture()

            self.stream = stream
            recordingOutput = output
            outputURL = url
            recordingID = UUID()
            state = .recording(since: .now)
            Log.capture.info("Recording started")
        } catch {
            state = .idle
            throw error
        }
    }

    /// Stops recording. The finished file arrives through `onFinish`.
    func stop() {
        guard case .recording = state, let stream, let id = recordingID else { return }
        state = .finishing
        Task {
            do {
                try await stream.stopCapture()
            } catch {
                Log.capture.error("Stopping the stream failed: \(error.localizedDescription, privacy: .public)")
            }
            // Give the recording output a moment to report; then finish with whatever was written.
            try? await Task.sleep(for: .seconds(4))
            finish(id: id, error: nil)
        }
    }

    private func finish(id: UUID?, error: (any Error)?) {
        guard let id, id == recordingID else { return }
        recordingID = nil
        let url = outputURL
        stream = nil
        recordingOutput = nil
        outputURL = nil
        state = .idle

        if let error {
            Log.capture.error("Recording failed: \(error.localizedDescription, privacy: .public)")
            onFinish?(.failure(error))
        } else if let url, FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            Log.capture.info("Recording finished")
            onFinish?(.success(url))
        } else {
            onFinish?(.failure(RecordingError.nothingRecorded))
        }
    }

    private static func makeStream(for target: RecordingTarget, options: RecordingOptions) async throws -> (SCContentFilter, SCStreamConfiguration) {
        guard CGPreflightScreenCaptureAccess() else { throw CaptureError.permissionDenied }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        let configuration = SCStreamConfiguration()
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(options.framesPerSecond, 1)))
        configuration.showsCursor = options.showsCursor
        configuration.queueDepth = 6
        configuration.capturesAudio = options.recordsSystemAudio
        configuration.excludesCurrentProcessAudio = true
        configuration.captureMicrophoneAudio = options.recordsMicrophone

        let filter: SCContentFilter
        let size: CGSize
        switch target {
        case .display(let displayID, let rect):
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw CaptureError.displayNotFound
            }
            let ownProcess = ProcessInfo.processInfo.processIdentifier
            let ownApps = content.applications.filter { $0.processID == ownProcess }
            filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            if let rect {
                configuration.sourceRect = rect
                size = rect.size
            } else {
                size = CGSize(width: display.width, height: display.height)
            }
        case .window(let windowID):
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw CaptureError.windowNotFound
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            size = filter.contentRect.size
        }

        // Video encoders want even dimensions.
        configuration.width = max(2, Int((size.width * options.scale).rounded()) / 2 * 2)
        configuration.height = max(2, Int((size.height * options.scale).rounded()) / 2 * 2)
        return (filter, configuration)
    }
}

nonisolated enum RecordingError: LocalizedError {
    case nothingRecorded

    var errorDescription: String? {
        String(localized: "The recording stopped before anything was captured.")
    }
}

extension ScreenRecorder: SCRecordingOutputDelegate, SCStreamDelegate {
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.finish(id: self.recordingID, error: nil) }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        Task { @MainActor in self.finish(id: self.recordingID, error: error) }
    }

    /// Called when macOS stops the stream, such as from the screen-sharing menu bar item.
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor in
            Log.capture.info("Stream stopped by the system: \(error.localizedDescription, privacy: .public)")
            let id = self.recordingID
            if case .recording = self.state {
                self.state = .finishing
            }
            try? await Task.sleep(for: .seconds(2))
            self.finish(id: id, error: nil)
        }
    }
}
