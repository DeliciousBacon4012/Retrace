import CoreGraphics
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
    var isEmpty: Bool { lines.isEmpty && codes.isEmpty }

    /// The first code that is a web address, for an Open button.
    var link: URL? {
        codes.lazy.compactMap { URL(string: $0) }.first { $0.scheme == "https" || $0.scheme == "http" }
    }
}

/// What the editor can hide automatically.
nonisolated enum SensitiveKind: String, CaseIterable, Identifiable, Sendable {
    case personal
    case faces
    case allText

    var id: Self { self }

    var title: String {
        switch self {
        case .personal: String(localized: "Emails, Phone Numbers, and Cards")
        case .faces: String(localized: "Faces")
        case .allText: String(localized: "All Text")
        }
    }

    var symbolName: String {
        switch self {
        case .personal: "person.text.rectangle"
        case .faces: "face.dashed"
        case .allText: "text.viewfinder"
        }
    }
}

/// On-device text, code, and face recognition with Vision. Nothing leaves the Mac.
///
/// Requests run on a dedicated queue with Vision's synchronous request handler, and every
/// call has a time limit, so a stuck model can never leave the app waiting forever.
nonisolated enum TextRecognizer {
    enum RecognitionError: LocalizedError {
        case timedOut

        var errorDescription: String? {
            String(localized: "Reading the text took too long.")
        }
    }

    private static let queue = DispatchQueue(label: "io.github.deliciousbacon4012.Untitled.vision", qos: .userInitiated)
    private static let log = Logger(subsystem: Log.subsystem, category: "text")

    /// Reads every line of text and every QR code or barcode.
    static func recognize(_ image: CGImage) async throws -> RecognizedContent {
        try await run(limit: .seconds(20)) {
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

    /// Areas worth hiding before sharing, in image pixels with the origin at the top left.
    static func sensitiveAreas(in image: CGImage, kinds: Set<SensitiveKind>) async throws -> [CGRect] {
        try await run(limit: .seconds(30)) {
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

    private static func textRequest(correctsLanguage: Bool) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
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

    /// Runs `work` on the Vision queue and gives up after `limit`, whichever comes first.
    private static func run<T: Sendable>(limit: Duration, _ work: @escaping @Sendable () throws -> T) async throws -> T {
        let started = ContinuousClock.now
        defer { log.info("Vision work took \(started.duration(to: .now), privacy: .public)") }
        return try await withCheckedThrowingContinuation { continuation in
            let finished = OSAllocatedUnfairLock(initialState: false)
            let finish: @Sendable (Result<T, any Error>) -> Void = { result in
                let first = finished.withLock { done in
                    defer { done = true }
                    return !done
                }
                if first { continuation.resume(with: result) }
            }
            queue.async {
                finish(Result { try work() })
            }
            let seconds = Double(limit.components.seconds)
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                log.error("Vision work timed out")
                finish(.failure(RecognitionError.timedOut))
            }
        }
    }
}
