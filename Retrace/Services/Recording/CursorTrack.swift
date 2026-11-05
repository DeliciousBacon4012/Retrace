import AppKit
import CoreImage

/// Where the cursor was during a recording, in the movie's pixels with the origin at the bottom
/// left, which is how Core Image counts.
nonisolated struct CursorTrack: Sendable {
    struct Sample: Sendable {
        /// Seconds since the movie's first frame.
        var time: Double
        var position: CGPoint
        /// Which entry of `images` the cursor looked like. `nil` means it was hidden or outside.
        var image: Int?
    }

    struct Image: @unchecked Sendable {
        var image: CGImage
        /// In movie pixels.
        var size: CGSize
        /// The click point, from the image's bottom left, in movie pixels.
        var hotSpot: CGPoint
    }

    var samples: [Sample] = []
    var images: [Image] = []

    /// The sample in effect at `time`, with the position blended between its neighbors.
    func sample(at time: Double) -> Sample? {
        guard let first = samples.first, let last = samples.last else { return nil }
        if time <= first.time { return first }
        if time >= last.time { return last }
        var low = 0
        var high = samples.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if samples[middle].time <= time { low = middle } else { high = middle }
        }
        let before = samples[low]
        let after = samples[high]
        let span = after.time - before.time
        let progress = span > 0 ? (time - before.time) / span : 0
        return Sample(
            time: time,
            position: CGPoint(
                x: before.position.x + (after.position.x - before.position.x) * progress,
                y: before.position.y + (after.position.y - before.position.y) * progress
            ),
            image: before.image
        )
    }
}

/// Follows the pointer while a recording runs. It reads the same pointer position and cursor
/// image the Dock and every other app can see; nothing is written anywhere until the movie is
/// finished.
final class CursorTracker {
    private static let samplesPerSecond = 120.0
    /// Asking macOS for the cursor's image is slow, and doing it often makes the real pointer
    /// flicker, so it's looked up a few times a second, only while the pointer rests and no
    /// button is down, and at least once a second regardless.
    private static let imageCheckInterval = 30
    private static let imageCheckLongest = 120

    private let area: CGRect
    private let pixelsPerPoint: CGFloat
    private var track = CursorTrack()
    private var timer: Timer?
    /// When the movie's first frame was written, in system uptime. Samples are kept in uptime
    /// until then, so the delay before the recorder says it started can be taken back out.
    private var movieStart: TimeInterval?
    private var tick = 0
    private var ticksSinceImageCheck = 0
    private var lastLocation: CGPoint?
    private var currentImage: Int?
    private var imageIDs: [Int: Int] = [:]

    /// - Parameter area: The recorded part of the screen, in global screen points.
    init(area: CGRect, pixelsPerPoint: CGFloat) {
        self.area = area
        self.pixelsPerPoint = pixelsPerPoint
    }

    /// Starts following the pointer. Call it before the recording starts, so nothing is missed.
    func start() {
        guard timer == nil else { return }
        updateImage()
        sample()
        let timer = Timer(timeInterval: 1 / Self.samplesPerSecond, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        // Keeps sampling while a menu is open or something else is tracking the pointer.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Lines the samples up with the movie: `uptime` is when its first frame was written.
    func movieBegan(atUptime uptime: TimeInterval) {
        movieStart = uptime
    }

    /// Stops and returns the track, timed from the movie's first frame.
    func stop() -> CursorTrack {
        timer?.invalidate()
        timer = nil
        let origin = movieStart ?? track.samples.first?.time ?? 0
        var result = track
        result.samples = track.samples.compactMap { sample in
            var sample = sample
            sample.time -= origin
            // Only the last moment before the first frame matters, for blending into it.
            return sample.time >= -0.25 ? sample : nil
        }
        return result
    }

    private func sample() {
        tick += 1
        ticksSinceImageCheck += 1
        let location = NSEvent.mouseLocation
        let isResting = location == lastLocation && NSEvent.pressedMouseButtons == 0
        lastLocation = location
        if (isResting && ticksSinceImageCheck >= Self.imageCheckInterval) || ticksSinceImageCheck >= Self.imageCheckLongest {
            updateImage()
        }
        track.samples.append(CursorTrack.Sample(
            time: ProcessInfo.processInfo.systemUptime,
            position: CGPoint(
                x: (location.x - area.minX) * pixelsPerPoint,
                y: (location.y - area.minY) * pixelsPerPoint
            ),
            image: currentImage
        ))
    }

    private func updateImage() {
        ticksSinceImageCheck = 0
        guard let cursor = NSCursor.currentSystem else { return }
        var rect = CGRect(origin: .zero, size: cursor.image.size)
        guard let image = cursor.image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return }
        // Cheaper than encoding the image to compare it: its pixels' hash, size, and hot spot.
        var hasher = Hasher()
        hasher.combine(image.dataProvider?.data.map { $0 as Data })
        hasher.combine(image.width)
        hasher.combine(image.height)
        hasher.combine(cursor.hotSpot.x)
        hasher.combine(cursor.hotSpot.y)
        let key = hasher.finalize()
        if let known = imageIDs[key] {
            currentImage = known
            return
        }
        let size = CGSize(width: cursor.image.size.width * pixelsPerPoint, height: cursor.image.size.height * pixelsPerPoint)
        track.images.append(CursorTrack.Image(
            image: image,
            size: size,
            hotSpot: CGPoint(
                x: cursor.hotSpot.x * pixelsPerPoint,
                y: size.height - cursor.hotSpot.y * pixelsPerPoint
            )
        ))
        imageIDs[key] = track.images.count - 1
        currentImage = track.images.count - 1
    }
}

/// Draws a tracked cursor onto movie frames with motion blur.
nonisolated struct CursorCompositor: Sendable {
    let track: CursorTrack
    let mode: CursorBlurMode
    /// How long the shutter stays open, in seconds.
    let shutter: Double

    /// Copies of the cursor drawn along its path in Quality mode.
    private static let qualitySamples = 16
    /// Below this travel in pixels, blur would only soften a still cursor.
    private static let minimumBlurTravel: CGFloat = 1.5

    private let images: [CIImage]

    init(track: CursorTrack, mode: CursorBlurMode, shutter: Double) {
        self.track = track
        self.mode = mode
        self.shutter = shutter
        images = track.images.map { entry in
            let image = CIImage(cgImage: entry.image)
            return image.transformed(by: CGAffineTransform(
                scaleX: entry.size.width / max(image.extent.width, 1),
                y: entry.size.height / max(image.extent.height, 1)
            ))
        }
    }

    func composite(over frame: CIImage, at time: Double) -> CIImage {
        guard let cursor = cursorImage(at: time) else { return frame }
        return cursor.composited(over: frame).cropped(to: frame.extent)
    }

    func cursorImage(at time: Double) -> CIImage? {
        guard let center = track.sample(at: time), center.image != nil else { return nil }
        let start = track.sample(at: time - shutter / 2)?.position ?? center.position
        let end = track.sample(at: time + shutter / 2)?.position ?? center.position
        let travel = hypot(end.x - start.x, end.y - start.y)
        guard travel >= Self.minimumBlurTravel else { return placed(center) }

        switch mode {
        case .fast:
            guard let cursor = placed(center) else { return nil }
            return cursor.applyingFilter("CIMotionBlur", parameters: [
                kCIInputRadiusKey: travel / 2,
                kCIInputAngleKey: atan2(end.y - start.y, end.x - start.x),
            ])
        case .quality:
            return accumulated(around: time)
        }
    }

    /// Averages copies of the cursor across the shutter: each is drawn at a share of full
    /// opacity and added, which is what a real shutter does to light.
    private func accumulated(around time: Double) -> CIImage? {
        let weight = 1 / CGFloat(Self.qualitySamples)
        var result: CIImage?
        for index in 0..<Self.qualitySamples {
            let progress = (Double(index) + 0.5) / Double(Self.qualitySamples) - 0.5
            guard let sample = track.sample(at: time + progress * shutter), let copy = placed(sample) else { continue }
            let faded = copy.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: weight, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: weight, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: weight, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: weight),
            ])
            result = result.map { faded.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: $0]) } ?? faded
        }
        return result
    }

    private func placed(_ sample: CursorTrack.Sample) -> CIImage? {
        guard let index = sample.image, images.indices.contains(index) else { return nil }
        let hotSpot = track.images[index].hotSpot
        return images[index].transformed(by: CGAffineTransform(
            translationX: sample.position.x - hotSpot.x,
            y: sample.position.y - hotSpot.y
        ))
    }
}
