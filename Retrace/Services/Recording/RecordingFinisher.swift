import AVFoundation
import CoreImage
import OSLog

/// The optional second pass over a finished recording: compressing it to a chosen quality and
/// drawing the cursor with motion blur. ScreenCaptureKit's recording output has no settings for
/// either, so this reads the movie back and writes a new one.
///
/// The original is replaced only once the new movie is complete.
nonisolated enum RecordingFinisher {
    struct Options: Sendable {
        var codec: VideoCodec
        var quality: VideoQuality
        var encoder: VideoEncoderChoice
        var cursor: CursorTrack?
        var cursorBlurMode: CursorBlurMode = .quality
        /// Shutter length as a share of one frame.
        var cursorBlurAmount: Double = 0.5

        var isNeeded: Bool {
            cursor != nil || quality != .original
        }
    }

    enum FinishError: LocalizedError {
        case noVideo
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .noVideo: String(localized: "The recording has no video to process.")
            case .failed(let reason): String(localized: "The recording couldn't be processed: \(reason)")
            }
        }
    }

    static func process(_ url: URL, options: Options) async throws {
        guard options.isNeeded else { return }
        let fileManager = FileManager.default
        let folder = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
        defer { try? fileManager.removeItem(at: folder) }
        let copy = folder.appendingPathComponent(url.lastPathComponent)
        try await write(url, to: copy, options: options)
        _ = try fileManager.replaceItemAt(url, withItemAt: copy)
    }

    private static func write(_ source: URL, to destination: URL, options: Options) async throws {
        let asset = AVURLAsset(url: source)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { throw FinishError.noVideo }
        let size = try await videoTrack.load(.naturalSize)
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let framesPerSecond = frameRate > 0 ? Double(frameRate) : 60
        let width = Int(size.width)
        let height = Int(size.height)

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mov)

        var pairs: [Pair] = []

        // Video goes through a composition so Core Image can draw on each frame.
        let shutter = options.cursorBlurAmount / framesPerSecond
        let compositor = options.cursor.map { CursorCompositor(track: $0, mode: options.cursorBlurMode, shutter: shutter) }
        let composition = try await AVVideoComposition.videoComposition(with: asset, applyingCIFiltersWithHandler: { request in
            let time = request.compositionTime.seconds
            let frame = request.sourceImage
            request.finish(with: compositor?.composite(over: frame, at: time) ?? frame, context: nil)
        })
        let videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: [videoTrack], videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        videoOutput.videoComposition = composition
        guard reader.canAdd(videoOutput) else { throw FinishError.failed("video output") }
        reader.add(videoOutput)

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings(
            options: options, width: width, height: height, framesPerSecond: framesPerSecond
        ))
        guard writer.canAdd(videoInput) else { throw FinishError.failed("video input") }
        writer.add(videoInput)
        pairs.append(Pair(output: videoOutput, input: videoInput, reader: reader, writer: writer))

        // Audio is copied untouched, track for track.
        for track in try await asset.loadTracks(withMediaType: .audio) {
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            let hint = try await track.load(.formatDescriptions).first
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: hint)
            guard reader.canAdd(output), writer.canAdd(input) else { continue }
            reader.add(output)
            writer.add(input)
            pairs.append(Pair(output: output, input: input, reader: reader, writer: writer))
        }

        guard reader.startReading() else { throw FinishError.failed(reader.error?.localizedDescription ?? "reader") }
        guard writer.startWriting() else { throw FinishError.failed(writer.error?.localizedDescription ?? "writer") }
        writer.startSession(atSourceTime: .zero)

        for pair in pairs {
            await pair.start()
        }
        for pair in pairs {
            await pair.finished()
        }

        if reader.status == .failed {
            writer.cancelWriting()
            throw FinishError.failed(reader.error?.localizedDescription ?? "reader")
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw FinishError.failed(writer.error?.localizedDescription ?? "writer")
        }
    }

    static func videoSettings(options: Options, width: Int, height: Int, framesPerSecond: Double) -> [String: Any] {
        var settings: [String: Any] = [
            AVVideoCodecKey: options.codec.codecType,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        // ProRes has no bit rate to choose; its name already says how much it keeps.
        if !options.codec.isProRes {
            var compression: [String: Any] = [AVVideoExpectedSourceFrameRateKey: framesPerSecond]
            // "Original" with a cursor pass still has to re-encode. It gets the high setting.
            let quality = options.quality == .original ? VideoQuality.high : options.quality
            compression[AVVideoAverageBitRateKey] = quality.bitRate(width: width, height: height, framesPerSecond: framesPerSecond)
            settings[AVVideoCompressionPropertiesKey] = compression
        }
        if let specification = options.encoder.specification {
            settings[AVVideoEncoderSpecificationKey] = specification
        }
        return settings
    }

    /// One reader output feeding one writer input, on its own queue so audio and video can't
    /// hold each other up.
    private final class Pair: @unchecked Sendable {
        private let output: AVAssetReaderOutput
        private let input: AVAssetWriterInput
        private let reader: AVAssetReader
        private let writer: AVAssetWriter
        private let queue = DispatchQueue(label: "Retrace.RecordingFinisher", qos: .userInitiated)
        private let done = DispatchGroup()

        init(output: AVAssetReaderOutput, input: AVAssetWriterInput, reader: AVAssetReader, writer: AVAssetWriter) {
            self.output = output
            self.input = input
            self.reader = reader
            self.writer = writer
        }

        func start() async {
            done.enter()
            input.requestMediaDataWhenReady(on: queue) { [self] in
                while input.isReadyForMoreMediaData {
                    guard writer.status == .writing, reader.status == .reading,
                          let sample = output.copyNextSampleBuffer(),
                          input.append(sample)
                    else {
                        input.markAsFinished()
                        done.leave()
                        return
                    }
                }
            }
        }

        func finished() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                done.notify(queue: queue) { continuation.resume() }
            }
        }
    }
}
