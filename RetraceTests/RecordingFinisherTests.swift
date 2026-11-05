import AVFoundation
import CoreImage
import XCTest
@testable import Retrace

final class RecordingFinisherTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "RetraceFinisher-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testOriginalWithNoCursorSkipsTheSecondPass() {
        let options = RecordingFinisher.Options(codec: .hevc, quality: .original, encoder: .automatic, cursor: nil)
        XCTAssertFalse(options.isNeeded)
    }

    func testTrackBlendsPositionsAndHoldsAtItsEnds() {
        let track = makeTrack()
        XCTAssertEqual(try XCTUnwrap(track.sample(at: 0.5)).position.x, 200, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(track.sample(at: -1)).position.x, 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(track.sample(at: 99)).position.x, 400, accuracy: 0.001)
    }

    func testStillCursorStaysSharpInEveryMode() throws {
        var track = makeTrack()
        track.samples = [
            .init(time: 0, position: CGPoint(x: 50, y: 50), image: 0),
            .init(time: 1, position: CGPoint(x: 50, y: 50), image: 0),
        ]
        for mode in CursorBlurMode.allCases {
            let cursor = try XCTUnwrap(CursorCompositor(track: track, mode: mode, shutter: 0.05).cursorImage(at: 0.5))
            XCTAssertEqual(cursor.extent.width, 20, accuracy: 0.5, "\(mode)")
        }
    }

    func testMovingCursorSmearsAlongItsPath() throws {
        let track = makeTrack()
        for mode in CursorBlurMode.allCases {
            let cursor = try XCTUnwrap(CursorCompositor(track: track, mode: mode, shutter: 0.1).cursorImage(at: 0.5))
            // 400 px/s for 0.1 s is 40 px of travel on a 20 px cursor.
            XCTAssertGreaterThan(cursor.extent.width, 40, "\(mode)")
        }
    }

    func testHiddenCursorDrawsNothing() {
        var track = makeTrack()
        track.samples = [.init(time: 0, position: .zero, image: nil)]
        XCTAssertNil(CursorCompositor(track: track, mode: .quality, shutter: 0.05).cursorImage(at: 0))
    }

    func testProcessingDrawsTheCursorAndKeepsTheMovieLength() async throws {
        let url = folder.appending(path: "movie.mov")
        try await writeMovie(to: url, frames: 30, framesPerSecond: 30, width: 320, height: 240)
        let before = try await AVURLAsset(url: url).load(.duration).seconds

        for mode in CursorBlurMode.allCases {
            try await RecordingFinisher.process(url, options: .init(
                codec: .hevc,
                quality: .balanced,
                encoder: .automatic,
                cursor: makeTrack(),
                cursorBlurMode: mode,
                cursorBlurAmount: 0.5
            ))
        }

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, before, accuracy: 0.1)

        // The frames are solid black, so anything bright along the path is the cursor.
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(value: 15, timescale: 30)).image
        XCTAssertGreaterThan(brightPixels(in: image), 50)
    }

    func testProResGetsNoBitRate() {
        let settings = RecordingFinisher.videoSettings(
            options: .init(codec: .proRes422, quality: .high, encoder: .automatic, cursor: nil),
            width: 100, height: 100, framesPerSecond: 30
        )
        XCTAssertNil(settings[AVVideoCompressionPropertiesKey])
    }

    // MARK: Helpers

    /// A white cursor moving across the frame at 400 pixels a second.
    private func makeTrack() -> CursorTrack {
        let context = CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        var track = CursorTrack()
        track.images = [.init(image: context.makeImage()!, size: CGSize(width: 20, height: 20), hotSpot: .zero)]
        track.samples = stride(from: 0.0, through: 1.0, by: 1.0 / 120).map {
            .init(time: $0, position: CGPoint(x: 400 * $0, y: 100), image: 0)
        }
        return track
    }

    private func brightPixels(in image: CGImage) -> Int {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return stride(from: 0, to: data.count, by: 4).lazy.filter { data[$0] > 60 }.count
    }

    private func writeMovie(to url: URL, frames: Int, framesPerSecond: Int32, width: Int, height: Int) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for index in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), 0, CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: framesPerSecond))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
    }
}
