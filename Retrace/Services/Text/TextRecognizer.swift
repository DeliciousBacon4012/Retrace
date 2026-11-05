import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
import Foundation
import os
import OSLog
import Vision

/// Text and codes found in an image, with where each line sits.
nonisolated struct RecognizedContent: Sendable {
    struct Line: Sendable {
        let text: String
        /// In image pixels, origin at the top left.
        let rect: CGRect
    }

    var lines: [Line] = []
    /// Payloads of QR codes and barcodes.
    var codes: [String] = []

    var text: String { lines.map(\.text).joined(separator: "\n") }
    var isEmpty: Bool { copiedText(preservingLineBreaks: true).isEmpty }

    /// OCR text ready for the clipboard or a document. The default keeps Vision's line order;
    /// disabling line breaks joins the same lines into a paragraph without changing their text.
    func copiedText(preservingLineBreaks: Bool) -> String {
        let lineParts = lines
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let parts = lineParts.isEmpty ? codes : lineParts
        let separator = preservingLineBreaks ? "\n" : " "
        return parts.joined(separator: separator)
    }

    /// The first code that is a web address, for an Open button.
    var link: URL? {
        codes.lazy.compactMap { URL(string: $0) }.first { $0.scheme == "https" || $0.scheme == "http" }
    }
}

/// A line of text in an image and the words in it, in image pixels, origin at the top left.
nonisolated struct TextLine: Sendable {
    let rect: CGRect
    let words: [CGRect]
}

/// What the editor can hide automatically.
nonisolated enum SensitiveKind: String, CaseIterable, Identifiable, Sendable {
    case personal
    case faces
    case people
    case allText

    var id: Self { self }

    var title: String {
        switch self {
        case .personal: String(localized: "Emails, Phone Numbers, and Cards")
        case .faces: String(localized: "Faces")
        case .people: String(localized: "People")
        case .allText: String(localized: "All Text")
        }
    }

    var symbolName: String {
        switch self {
        case .personal: "person.text.rectangle"
        case .faces: "face.dashed"
        case .people: "person.crop.rectangle"
        case .allText: "text.viewfinder"
        }
    }
}

/// On-device text, code, face, person, and saliency recognition with Vision. Nothing leaves the Mac.
///
/// Requests run on a dedicated queue with Vision's synchronous request handler, and every
/// call has a time limit, so a stuck model can never leave the app waiting forever.
nonisolated enum TextRecognizer {
    enum RecognitionError: LocalizedError {
        case timedOut
        case imageTooLarge
        case maskRenderingFailed

        var errorDescription: String? {
            switch self {
            case .timedOut: String(localized: "Image analysis took too long.")
            case .imageTooLarge: String(localized: "This image is too large to analyze safely.")
            case .maskRenderingFailed: String(localized: "The subject mask couldn't be rendered.")
            }
        }
    }

    private static let queue = DispatchQueue(label: "io.github.deliciousbacon4012.Retrace.vision", qos: .userInitiated)
    private static let log = Logger(subsystem: Log.subsystem, category: "text")
    /// Seconds a call may wait, counting any work ahead of it. The first read by a new build of
    /// the app, or after an OS update, makes Vision set up its models: about 45 seconds when measured.
    private static let timeLimit: TimeInterval = 120
    private static let maximumImageDimension = 16_384
    private static let maximumImagePixels = 40_000_000
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Sets up Vision's models ahead of the first read. The system keeps them for this build of
    /// the app, so later launches take a moment. Text has to be drawn: a blank image never gets
    /// as far as the recognizer.
    static func prepare() {
        queue.async(qos: .utility, flags: .enforceQoS) {
            guard let image = warmUpImage() else { return }
            let started = ContinuousClock.now
            do {
                let request = textRequest(correctsLanguage: true)
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                log.info("Vision ready after \(started.duration(to: .now), privacy: .public), read \(request.results?.count ?? 0, privacy: .public) lines")
            } catch {
                log.error("Preparing Vision failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Reads every line of text and every QR code or barcode.
    static func recognize(_ image: CGImage) async throws -> RecognizedContent {
        try validateImageSize(image)
        return try await run {
            let text = textRequest(correctsLanguage: true)
            let codes = VNDetectBarcodesRequest()
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([text, codes])

            let size = CGSize(width: image.width, height: image.height)
            var content = RecognizedContent()
            content.lines = (text.results ?? []).compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return RecognizedContent.Line(text: candidate.string, rect: pixelRect(observation.boundingBox, in: size))
            }
            var seen = Set<String>()
            content.codes = (codes.results ?? []).compactMap(\.payloadStringValue).filter { seen.insert($0).inserted }
            log.info("Read \(content.lines.count, privacy: .public) lines and \(content.codes.count, privacy: .public) codes")
            return content
        }
    }

    /// Where each line of text sits, with a box for every word, for snapping marks to text.
    /// In image pixels with the origin at the top left.
    static func textLayout(in image: CGImage) async throws -> [TextLine] {
        try validateImageSize(image)
        let lines: [TextLine] = try await run {
            let size = CGSize(width: image.width, height: image.height)
            let request = textRequest(correctsLanguage: false)
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            return (request.results ?? []).compactMap { observation -> TextLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let line = pixelRect(observation.boundingBox, in: size)
                var words: [CGRect] = []
                let text = candidate.string
                text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { _, range, _, _ in
                    guard let box = (try? candidate.boundingBox(for: range))?.boundingBox else { return }
                    let word = pixelRect(box, in: size)
                    // Vision sometimes answers with the whole line; that box says nothing about the word.
                    if word.width < line.width * 0.98 { words.append(word) }
                }
                return TextLine(rect: line, words: words)
            }
        }
        return lines
    }

    /// Areas worth hiding before sharing, in image pixels with the origin at the top left.
    static func sensitiveAreas(in image: CGImage, kinds: Set<SensitiveKind>) async throws -> [CGRect] {
        try validateImageSize(image)
        return try await run {
            let size = CGSize(width: image.width, height: image.height)
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            var areas: [CGRect] = []

            if kinds.contains(.faces) {
                let faces = VNDetectFaceRectanglesRequest()
                try handler.perform([faces])
                areas += (faces.results ?? []).map { face in
                    let rect = pixelRect(face.boundingBox, in: size)
                    // Faces read better hidden with a little room around them.
                    return rect.insetBy(dx: -rect.width * 0.15, dy: -rect.height * 0.2)
                }
            }

            if kinds.contains(.people) {
                let people = VNDetectHumanRectanglesRequest()
                people.upperBodyOnly = false
                try handler.perform([people])
                areas += (people.results ?? []).map { person in
                    let rect = pixelRect(person.boundingBox, in: size)
                    // Leave room around body edges so the redaction covers the whole person.
                    return rect.insetBy(dx: -rect.width * 0.08, dy: -rect.height * 0.06)
                }
            }

            if kinds.contains(.personal) || kinds.contains(.allText) {
                let text = textRequest(correctsLanguage: false)
                try handler.perform([text])
                for observation in text.results ?? [] {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    let lineRect = pixelRect(observation.boundingBox, in: size)
                    if kinds.contains(.allText) {
                        areas.append(lineRect)
                        continue
                    }
                    for range in sensitiveRanges(in: candidate.string) {
                        let box = (try? candidate.boundingBox(for: range))?.boundingBox
                        areas.append(box.map { pixelRect($0, in: size) } ?? lineRect)
                    }
                }
            }

            let bounds = CGRect(origin: .zero, size: size)
            return areas
                .map { $0.insetBy(dx: -3, dy: -3).intersection(bounds).integral }
                .filter { !$0.isNull && $0.width > 2 && $0.height > 2 }
        }
    }

    /// Suggests a crop around what Vision finds most salient, in top-left image pixels.
    static func attentionCrop(in image: CGImage, mode: SmartCropMode = .automatic) async throws -> CGRect? {
        try validateImageSize(image)
        return try await ImageIntelligence.suggestedCrop(in: image, mode: mode)
    }

    /// Isolates all detected foreground instances with a transparent background.
    static func liftedSubject(in image: CGImage) async throws -> CGImage? {
        try validateImageSize(image)
        return try await run {
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            let request = VNGenerateForegroundInstanceMaskRequest()
            try handler.perform([request])
            guard let observation = request.results?.first else { return nil }
            // Apple documents allInstances as excluding the background already.
            let instances = observation.allInstances
            guard !instances.isEmpty else { return nil }

            let maskBuffer = try observation.generateScaledMaskForImage(forInstances: instances, from: handler)
            return try composeForeground(image, mask: CIImage(cvPixelBuffer: maskBuffer))
        }
    }

    /// Composites a grayscale mask over a transparent background, scaled to source pixels.
    /// Kept separate so alpha behavior can be verified without relying on Vision's model output.
    static func composeForeground(_ image: CGImage, mask: CIImage) throws -> CGImage {
        try validateImageSize(image)
        let input = CIImage(cgImage: image)
        let maskBounds = mask.extent
        guard maskBounds.width.isFinite, maskBounds.height.isFinite,
              maskBounds.width > 0, maskBounds.height > 0
        else { throw RecognitionError.maskRenderingFailed }

        let normalizedMask = mask.transformed(by: CGAffineTransform(translationX: -maskBounds.minX, y: -maskBounds.minY))
        let scaledMask = normalizedMask
            .transformed(by: CGAffineTransform(
                scaleX: input.extent.width / maskBounds.width,
                y: input.extent.height / maskBounds.height
            ))
            .cropped(to: input.extent)
        let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: input.extent)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = input
        blend.backgroundImage = clear
        blend.maskImage = scaledMask
        guard let output = blend.outputImage?.cropped(to: input.extent),
              let result = ciContext.createCGImage(output, from: input.extent)
        else { throw RecognitionError.maskRenderingFailed }
        return result
    }

    /// Emails, phone numbers, and card-like numbers in a line of text.
    static func sensitiveRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber]
        if let detector = try? NSDataDetector(types: types.rawValue) {
            let whole = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, range: whole) {
                if match.resultType == .link, match.url?.scheme != "mailto" { continue }
                if let range = Range(match.range, in: text) { ranges.append(range) }
            }
        }
        // Card and account numbers: 12 to 19 digits, maybe split by spaces or dashes.
        let cards = /\b(?:\d[ -]?){11,18}\d\b/
        for match in text.matches(of: cards) where !ranges.contains(where: { $0.overlaps(match.range) }) {
            ranges.append(match.range)
        }
        // Emails NSDataDetector misses when there's no mailto context.
        let emails = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/
        for match in text.matches(of: emails) where !ranges.contains(where: { $0.overlaps(match.range) }) {
            ranges.append(match.range)
        }
        return ranges
    }

    // MARK: Helpers

    private static func validateImageSize(_ image: CGImage) throws {
        guard image.width > 0, image.height > 0,
              image.width <= maximumImageDimension, image.height <= maximumImageDimension,
              image.width <= maximumImagePixels / image.height
        else { throw RecognitionError.imageTooLarge }
    }

    private static func textRequest(correctsLanguage: Bool) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = TextRecognitionSpeed.current == .fast ? .fast : .accurate
        request.usesLanguageCorrection = correctsLanguage
        request.automaticallyDetectsLanguage = true
        return request
    }

    /// Vision's normalized, bottom-left rectangles in top-left image pixels.
    private static func pixelRect(_ normalized: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: normalized.minX * size.width,
            y: (1 - normalized.maxY) * size.height,
            width: normalized.width * size.width,
            height: normalized.height * size.height
        )
    }

    /// A line of black text on white, for `prepare()`.
    private static func warmUpImage() -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: 600,
            height: 120,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 600, height: 120))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 36, nil),
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Getting ready to read", attributes: attributes))
        context.textPosition = CGPoint(x: 20, y: 40)
        CTLineDraw(line, context)
        return context.makeImage()
    }

    /// Runs `work` on the Vision queue and gives up after `timeLimit`, whichever comes first.
    private static func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        let started = ContinuousClock.now
        defer { log.info("Vision work took \(started.duration(to: .now), privacy: .public)") }
        return try await withCheckedThrowingContinuation { continuation in
            let finished = OSAllocatedUnfairLock(initialState: false)
            let finish: @Sendable (Result<T, any Error>) -> Bool = { result in
                let first = finished.withLock { done in
                    defer { done = true }
                    return !done
                }
                if first { continuation.resume(with: result) }
                return first
            }
            queue.async {
                _ = finish(Result { try work() })
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeLimit) {
                if finish(.failure(RecognitionError.timedOut)) {
                    log.error("Vision work timed out")
                }
            }
        }
    }
}

nonisolated extension CGImage {
    /// Vision reads small crops better when they are bigger, so a small area is drawn at
    /// up to three times its size first. Returns `nil` when the image is big enough.
    func upscaledForReading() -> CGImage? {
        let shortSide = min(width, height)
        guard shortSide > 0, shortSide < 120 else { return nil }
        let factor = min(3, (120 / CGFloat(shortSide)).rounded(.up))
        let size = CGSize(width: CGFloat(width) * factor, height: CGFloat(height) * factor)
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // White behind any transparency, so text on clear pixels still has contrast.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.interpolationQuality = .high
        context.draw(self, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }
}
