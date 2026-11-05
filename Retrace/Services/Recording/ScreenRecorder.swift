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
    var color: VideoColor = .automatic
    var queueDepth: Int = 6
    var showsClicks: Bool = false
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
    /// Called when the movie's first frame is written, with no delay beyond a hop to the main actor.
    @ObservationIgnored var onRecordingBegan: (() -> Void)?

    @ObservationIgnored private var stream: SCStream?
    @ObservationIgnored private var recordingOutput: SCRecordingOutput?
    @ObservationIgnored private var outputURL: URL?
    /// Identifies the current recording, so late callbacks from an earlier one are ignored.
    @ObservationIgnored private var recordingID: UUID?
    @ObservationIgnored private var stopRequested = false
    @ObservationIgnored private var streamDidStop = false
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var outputCompletion: OutputCompletion?
    @ObservationIgnored private var outputCompletionContinuation: CheckedContinuation<OutputCompletion, Never>?
    @ObservationIgnored private var finalizationTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var stopCaptureFinished = false
    @ObservationIgnored private var stopCaptureError: (any Error)?

    private enum OutputCompletion {
        case finished
        case failed(any Error)
        case timedOut
    }

    private static let finalizationTimeout: Duration = .seconds(60)

    var isActive: Bool { state != .idle }

    func start(_ target: RecordingTarget, options: RecordingOptions, to url: URL) async throws {
        guard state == .idle else { return }
        let id = UUID()
        recordingID = id
        outputURL = url
        stopRequested = false
        streamDidStop = false
        stopTask = nil
        outputCompletion = nil
        outputCompletionContinuation = nil
        finalizationTimeoutTask = nil
        stopCaptureFinished = false
        stopCaptureError = nil
        state = .starting
        do {
            try Task.checkCancellation()
            let (filter, configuration) = try await Self.makeStream(for: target, options: options)
            try Task.checkCancellation()
            try checkStartIsCurrent(id)

            let outputConfiguration = SCRecordingOutputConfiguration()
            outputConfiguration.outputURL = url
            outputConfiguration.outputFileType = .mov
            // Fall back to HEVC if this Mac can't record the chosen codec directly.
            let available = outputConfiguration.availableVideoCodecTypes
            outputConfiguration.videoCodecType = available.contains(options.codec.codecType) ? options.codec.codecType : .hevc
            let output = SCRecordingOutput(configuration: outputConfiguration, delegate: self)

            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addRecordingOutput(output)
            self.stream = stream
            recordingOutput = output
            try checkStartIsCurrent(id)
            // Keep ScreenCaptureKit startup alive long enough to honor a stop/cancellation
            // request immediately after the framework reports whether startup succeeded.
            let captureStart = Task { try await stream.startCapture() }
            try await captureStart.value

            guard recordingID == id else { throw CancellationError() }
            if RecordingStartupPolicy.shouldStopAfterStart(
                stopRequested: stopRequested,
                taskCancelled: Task.isCancelled,
                outputAlreadyCompleted: outputCompletion != nil
            ) {
                state = .finishing
                await stopAndFinalize(id: id, stream: stream, output: output, url: url, stopStream: !streamDidStop)
                throw CancellationError()
            }
            state = .recording(since: .now)
            Log.capture.info("Recording started")
        } catch {
            let shouldSuppressError = stopRequested || error is CancellationError || Task.isCancelled
            if recordingID == id {
                cleanupFailedStart(id: id, url: url)
            }
            if shouldSuppressError {
                throw CancellationError()
            }
            throw error
        }
    }

    /// Stops recording. The finished file arrives through `onFinish`.
    func stop() {
        guard let id = recordingID else { return }
        switch state {
        case .idle, .finishing:
            return
        case .starting:
            stopRequested = true
            // If startCapture is already running, start() performs the stop as soon as it returns.
            return
        case .recording:
            guard let stream, let output = recordingOutput, let url = outputURL else { return }
            state = .finishing
            stopTask = Task { @MainActor [weak self] in
                await self?.stopAndFinalize(id: id, stream: stream, output: output, url: url, stopStream: true)
            }
        }
    }

    private func checkStartIsCurrent(_ id: UUID) throws {
        guard recordingID == id,
              !RecordingStartupPolicy.shouldCancelBeforeStartCapture(
                  stopRequested: stopRequested,
                  taskCancelled: Task.isCancelled
              ) else {
            throw CancellationError()
        }
    }

    private func stopAndFinalize(
        id: UUID,
        stream: SCStream,
        output: SCRecordingOutput,
        url: URL,
        stopStream: Bool
    ) async {
        guard recordingID == id else { return }

        stopCaptureFinished = !stopStream
        stopCaptureError = nil
        let completionTask = Task { @MainActor [weak self] in
            await self?.waitForFinalization(id: id) ?? .timedOut
        }
        if stopStream {
            Task { @MainActor [weak self] in
                do {
                    try await stream.stopCapture()
                    self?.completeStopCapture(id: id, error: nil, url: url)
                } catch {
                    Log.capture.error("Stopping the stream failed: \(error.localizedDescription, privacy: .public)")
                    self?.completeStopCapture(id: id, error: error, url: url)
                }
            }
        }
        let completion = await completionTask.value
        switch completion {
        case .finished:
            let exists = FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
            let byteCount = (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.size] as? NSNumber
            guard RecordingOutputValidation.isUsable(
                fileExists: exists,
                byteCount: byteCount?.intValue,
                duration: output.recordedDuration
            ) else {
                removePartialFile(at: url)
                finish(id: id, error: RecordingError.nothingRecorded)
                return
            }
            finish(id: id, error: nil)
        case .failed(let error):
            removePartialFile(at: url)
            finish(id: id, error: error)
        case .timedOut:
            // If stopCapture itself has not returned, ScreenCaptureKit may still own the file.
            // The stop task removes it later if the stream eventually stops.
            if stopCaptureFinished { removePartialFile(at: url) }
            finish(id: id, error: RecordingError.finalizationTimedOut)
        }
    }

    private func waitForFinalization(id: UUID) async -> OutputCompletion {
        guard recordingID == id else { return .failed(CancellationError()) }
        return await withCheckedContinuation { continuation in
            // Latch the delegate event too, because it may arrive before this waiter runs.
            outputCompletionContinuation = continuation
            finalizationTimeoutTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: Self.finalizationTimeout)
                } catch {
                    return
                }
                self?.timeOutFinalization(id: id)
            }
            resumeFinalizationIfReady(id: id)
        }
    }

    private func completeOutput(id: UUID, with completion: OutputCompletion) {
        guard recordingID == id, outputCompletion == nil else { return }
        outputCompletion = completion
        resumeFinalizationIfReady(id: id)
    }

    private func completeStopCapture(id: UUID, error: (any Error)?, url: URL) {
        guard recordingID == id else {
            if error == nil, outputURL != url {
                // The recording timed out but the stream eventually stopped. Remove its
                // incomplete file unless a newer session now owns that path.
                removePartialFile(at: url)
            }
            return
        }
        guard !stopCaptureFinished else { return }
        stopCaptureFinished = true
        stopCaptureError = error
        resumeFinalizationIfReady(id: id)
    }

    private func timeOutFinalization(id: UUID) {
        guard recordingID == id, outputCompletionContinuation != nil else { return }
        outputCompletion = .timedOut
        finalizationTimeoutTask = nil
        let continuation = outputCompletionContinuation
        outputCompletionContinuation = nil
        continuation?.resume(returning: .timedOut)
    }

    private func resumeFinalizationIfReady(id: UUID) {
        guard recordingID == id, let outputCompletion else { return }
        let result: OutputCompletion
        if case .timedOut = outputCompletion {
            result = .timedOut
        } else {
            guard stopCaptureFinished else { return }
            if let stopCaptureError {
                result = .failed(stopCaptureError)
            } else {
                result = outputCompletion
            }
        }
        finalizationTimeoutTask?.cancel()
        finalizationTimeoutTask = nil
        let continuation = outputCompletionContinuation
        outputCompletionContinuation = nil
        continuation?.resume(returning: result)
    }

    private func cleanupFailedStart(id: UUID, url: URL) {
        guard recordingID == id else { return }
        let outputWasAttached = recordingOutput != nil
        finalizationTimeoutTask?.cancel()
        finalizationTimeoutTask = nil
        outputCompletionContinuation?.resume(returning: .failed(CancellationError()))
        outputCompletionContinuation = nil
        self.stream = nil
        recordingOutput = nil
        outputURL = nil
        recordingID = nil
        stopRequested = false
        streamDidStop = false
        stopTask = nil
        outputCompletion = nil
        stopCaptureFinished = false
        stopCaptureError = nil
        state = .idle
        if outputWasAttached { removePartialFile(at: url) }
    }

    private func removePartialFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func finish(id: UUID, error: (any Error)?) {
        guard id == recordingID else { return }
        finalizationTimeoutTask?.cancel()
        finalizationTimeoutTask = nil
        outputCompletionContinuation = nil
        let url = outputURL
        recordingID = nil
        stream = nil
        recordingOutput = nil
        outputURL = nil
        stopRequested = false
        streamDidStop = false
        stopTask = nil
        outputCompletion = nil
        stopCaptureFinished = false
        stopCaptureError = nil
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
        guard ScreenAccess.isGranted else { throw CaptureError.permissionDenied }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        let configuration = SCStreamConfiguration()
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(options.framesPerSecond, 1)))
        configuration.showsCursor = options.showsCursor
        configuration.queueDepth = options.queueDepth
        configuration.showMouseClicks = options.showsClicks
        if let colorSpace = options.color.colorSpaceName {
            configuration.colorSpaceName = colorSpace
        }
        configuration.capturesAudio = options.recordsSystemAudio
        configuration.excludesCurrentProcessAudio = true
        configuration.captureMicrophone = options.recordsMicrophone

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
    case finalizationTimedOut

    var errorDescription: String? {
        switch self {
        case .nothingRecorded:
            String(localized: "The recording stopped before anything was captured.")
        case .finalizationTimedOut:
            String(localized: "The recording couldn't be finalized in time. Try recording again.")
        }
    }
}

/// Pure state decisions shared by the recorder and its XCTest coverage.
nonisolated enum RecordingStartupPolicy {
    static func shouldCancelBeforeStartCapture(stopRequested: Bool, taskCancelled: Bool) -> Bool {
        stopRequested || taskCancelled
    }

    static func shouldStopAfterStart(
        stopRequested: Bool,
        taskCancelled: Bool,
        outputAlreadyCompleted: Bool
    ) -> Bool {
        stopRequested || taskCancelled || outputAlreadyCompleted
    }
}

/// Rejects missing, empty, or zero-duration movies after ScreenCaptureKit reports finalization.
nonisolated enum RecordingOutputValidation {
    static func isUsable(fileExists: Bool, byteCount: Int?, duration: CMTime) -> Bool {
        fileExists
            && (byteCount ?? 0) > 0
            && duration.isNumeric
            && CMTimeCompare(duration, .zero) > 0
    }
}

extension ScreenRecorder: SCRecordingOutputDelegate, SCStreamDelegate {
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.onRecordingBegan?() }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        let outputID = ObjectIdentifier(recordingOutput)
        Task { @MainActor in
            guard self.recordingOutput.map(ObjectIdentifier.init) == outputID,
                  let id = self.recordingID else { return }
            self.completeOutput(id: id, with: .finished)
            self.finalizeIfRecording(id: id)
        }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        let outputID = ObjectIdentifier(recordingOutput)
        Task { @MainActor in
            guard self.recordingOutput.map(ObjectIdentifier.init) == outputID,
                  let id = self.recordingID else { return }
            self.completeOutput(id: id, with: .failed(error))
            self.finalizeIfRecording(id: id)
        }
    }

    private func finalizeIfRecording(id: UUID) {
        guard recordingID == id, case .recording = state,
              let stream, let output = recordingOutput, let url = outputURL else { return }
        state = .finishing
        stopTask = Task { @MainActor [weak self] in
            await self?.stopAndFinalize(id: id, stream: stream, output: output, url: url, stopStream: true)
        }
    }

    /// Called when macOS stops the stream, such as from the screen-sharing menu bar item.
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let streamID = ObjectIdentifier(stream)
        Task { @MainActor [weak self] in
            guard let self else { return }
            Log.capture.info("Stream stopped by the system: \(error.localizedDescription, privacy: .public)")
            guard self.stream.map(ObjectIdentifier.init) == streamID,
                  let id = self.recordingID,
                  let stream = self.stream,
                  let output = self.recordingOutput, let url = self.outputURL else { return }
            self.stopRequested = true
            self.streamDidStop = true
            guard case .recording = self.state else { return }
            self.state = .finishing
            self.stopTask = Task { @MainActor [weak self] in
                await self?.stopAndFinalize(id: id, stream: stream, output: output, url: url, stopStream: false)
            }
        }
    }
}
