import AVFoundation
import OSLog
import ScreenCaptureKit

/// Encodes the screen continuously into short fragmented-MP4 segments on disk and keeps
/// only the newest ones, so the last few minutes can be saved at any moment.
///
/// ScreenCaptureKit and AVFoundation call this on background queues, so it guards its
/// own state with a lock instead of using the main actor.
nonisolated final class ReplayWriter: NSObject, SCStreamOutput, AVAssetWriterDelegate, @unchecked Sendable {
    struct Configuration: Sendable {
        var width: Int
        var height: Int
        var framesPerSecond: Int
        var codec: VideoCodec
        var includesAudio: Bool
        var maximumSeconds: Double
        var maximumBytes: Int
    }

    private struct Segment {
        let url: URL
        let seconds: Double
        let bytes: Int
    }

    let sampleQueue = DispatchQueue(label: "io.github.deliciousbacon4012.Untitled.replay", qos: .userInitiated)

    private let configuration: Configuration
    private let directory: URL
    private let lock = NSLock()

    // Touched only on `sampleQueue`.
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var failed = false

    // Guarded by `lock`.
    private var initializationSegment: Data?
    private var segments: [Segment] = []
    private var segmentCounter = 0
    /// Snapshots being written. While any are, segments that age out are kept on disk until
    /// they finish, so a save never loses a piece it's reading.
    private var snapshotsInProgress = 0
    private var agedOutFiles: [URL] = []
    private var removesDirectoryAfterSnapshots = false

    /// Deletes replay folders and save files that a crash or force quit left in the temporary
    /// folder. Anything touched in the last 10 minutes is left alone, in case another copy of
    /// the app, such as a development build, is buffering right now.
    static func removeLeftovers() {
        let fileManager = FileManager.default
        let folder = fileManager.temporaryDirectory
        guard let items = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date.now.addingTimeInterval(-10 * 60)
        var removed = 0
        for item in items {
            let name = item.lastPathComponent
            guard name.hasPrefix("Replay-") || (name.hasPrefix("replay-") && name.hasSuffix(".mp4")) else { continue }
            let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            guard modified < cutoff else { continue }
            if (try? fileManager.removeItem(at: item)) != nil { removed += 1 }
        }
        if removed > 0 {
            Logger(subsystem: Log.subsystem, category: "replay").info("Removed \(removed, privacy: .public) leftover replay files")
        }
    }

    init(configuration: Configuration) throws {
        self.configuration = configuration
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Replay-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        super.init()
    }

    /// Seconds currently held.
    var bufferedSeconds: Double {
        lock.withLock { segments.reduce(0) { $0 + $1.seconds } }
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid, !failed else { return }
        switch type {
        case .screen:
            guard Self.isCompleteFrame(sampleBuffer) else { return }
            if writer == nil {
                startWriter(at: sampleBuffer.presentationTimeStamp)
            }
            if let videoInput, videoInput.isReadyForMoreMediaData {
                videoInput.append(sampleBuffer)
            }
        case .audio:
            guard writer?.status == .writing, let audioInput, audioInput.isReadyForMoreMediaData else { return }
            audioInput.append(sampleBuffer)
        default:
            break
        }
        if let writer, writer.status == .failed {
            failed = true
            Log.capture.error("Replay encoding failed: \(writer.error?.localizedDescription ?? "unknown", privacy: .public)")
        }
    }

    private func startWriter(at time: CMTime) {
        let writer = AVAssetWriter(contentType: .mpeg4Movie)
        writer.outputFileTypeProfile = .mpeg4AppleHLS
        writer.preferredOutputSegmentInterval = CMTime(seconds: 1, preferredTimescale: 600)
        writer.initialSegmentStartTime = time
        writer.delegate = self

        // About 0.1 bits per pixel per frame is plenty for screen content.
        let bitRate = max(2_000_000, Int(Double(configuration.width * configuration.height * configuration.framesPerSecond) * 0.1))
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: configuration.codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: configuration.width,
            AVVideoHeightKey: configuration.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoExpectedSourceFrameRateKey: configuration.framesPerSecond,
                AVVideoMaxKeyFrameIntervalDurationKey: 1,
            ],
        ])
        video.expectsMediaDataInRealTime = true
        guard writer.canAdd(video) else {
            failed = true
            return
        }
        writer.add(video)
        videoInput = video

        if configuration.includesAudio {
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000,
            ])
            audio.expectsMediaDataInRealTime = true
            if writer.canAdd(audio) {
                writer.add(audio)
                audioInput = audio
            }
        }

        guard writer.startWriting() else {
            failed = true
            Log.capture.error("Replay writer couldn't start: \(writer.error?.localizedDescription ?? "unknown", privacy: .public)")
            return
        }
        writer.startSession(atSourceTime: time)
        self.writer = writer
    }

    /// ScreenCaptureKit also sends "nothing changed" frames without pixels; only complete ones are encoded.
    private static func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus)
        else { return false }
        return status == .complete
    }

    // MARK: AVAssetWriterDelegate

    func assetWriter(_ writer: AVAssetWriter, didOutputSegmentData segmentData: Data, segmentType: AVAssetSegmentType, segmentReport: AVAssetSegmentReport?) {
        lock.withLock {
            switch segmentType {
            case .initialization:
                initializationSegment = segmentData
            case .separable:
                segmentCounter += 1
                let url = directory.appendingPathComponent("\(segmentCounter).m4s")
                do {
                    try segmentData.write(to: url)
                } catch {
                    Log.capture.error("Writing a replay segment failed: \(error.localizedDescription, privacy: .public)")
                    return
                }
                let seconds = segmentReport?.trackReports.map(\.duration.seconds).max() ?? 1
                segments.append(Segment(url: url, seconds: seconds.isFinite ? seconds : 1, bytes: segmentData.count))
                trim()
            @unknown default:
                break
            }
        }
    }

    /// Drops the oldest segments beyond the time and size limits. Call with `lock` held.
    private func trim() {
        var seconds = segments.reduce(0) { $0 + $1.seconds }
        var bytes = segments.reduce(0) { $0 + $1.bytes }
        while segments.count > 1,
              seconds - segments[0].seconds >= configuration.maximumSeconds || bytes > configuration.maximumBytes {
            let oldest = segments.removeFirst()
            seconds -= oldest.seconds
            bytes -= oldest.bytes
            if snapshotsInProgress > 0 {
                agedOutFiles.append(oldest.url)
            } else {
                try? FileManager.default.removeItem(at: oldest.url)
            }
        }
    }

    // MARK: Saving and stopping

    /// Writes the buffered segments into one playable fragmented MP4 file: all of them, or
    /// with `lastSeconds`, just enough of the newest to cover that long.
    func writeSnapshot(to url: URL, lastSeconds: Double? = nil) throws {
        let (header, files) = lock.withLock {
            snapshotsInProgress += 1
            return (initializationSegment, Self.newest(segments, covering: lastSeconds).map(\.url))
        }
        defer { lock.withLock { finishSnapshot() } }
        guard let header, !files.isEmpty else { throw ReplayError.empty }
        FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.write(contentsOf: header)
        for file in files {
            try handle.write(contentsOf: Data(contentsOf: file))
        }
    }

    /// The newest segments that together last at least `seconds`, plus one more so the
    /// exact cut always has a whole keyframe interval before it. All of them when nil.
    private static func newest(_ segments: [Segment], covering seconds: Double?) -> [Segment] {
        guard let seconds else { return segments }
        var total = 0.0
        var count = 0
        for segment in segments.reversed() {
            count += 1
            if total >= seconds { break }
            total += segment.seconds
        }
        return Array(segments.suffix(count))
    }

    /// Call with `lock` held when a snapshot is done, to delete what aged out meanwhile.
    private func finishSnapshot() {
        snapshotsInProgress -= 1
        guard snapshotsInProgress == 0 else { return }
        for file in agedOutFiles {
            try? FileManager.default.removeItem(at: file)
        }
        agedOutFiles.removeAll()
        if removesDirectoryAfterSnapshots {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// Stops encoding and deletes every buffered segment, once any save in progress is done.
    func shutDown() {
        sampleQueue.async { [self] in
            videoInput?.markAsFinished()
            audioInput?.markAsFinished()
            writer?.cancelWriting()
            writer = nil
            lock.withLock {
                segments.removeAll()
                initializationSegment = nil
                if snapshotsInProgress > 0 {
                    removesDirectoryAfterSnapshots = true
                } else {
                    try? FileManager.default.removeItem(at: directory)
                }
            }
        }
    }
}

nonisolated enum ReplayError: LocalizedError {
    case empty
    case notRunning

    var errorDescription: String? {
        switch self {
        case .empty: String(localized: "The replay buffer hasn't recorded anything yet.")
        case .notRunning: String(localized: "The replay buffer is off.")
        }
    }
}
