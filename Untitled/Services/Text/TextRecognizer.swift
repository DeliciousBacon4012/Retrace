import CoreGraphics
import Foundation
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
nonisolated enum TextRecognizer {
    /// Reads every line of text and every QR code or barcode.
    @concurrent
    static func recognize(_ image: CGImage) async throws -> RecognizedContent {
        let size = CGSize(width: image.width, height: image.height)

        var textRequest = RecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.automaticallyDetectsLanguage = true
        let observations = try await textRequest.perform(on: image)

        var content = RecognizedContent()
        content.lines = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedContent.Line(
                text: candidate.string,
                rect: observation.boundingBox.toImageCoordinates(size, origin: .upperLeft)
            )
        }

        let codes = (try? await DetectBarcodesRequest().perform(on: image)) ?? []
        var seen = Set<String>()
        content.codes = codes.compactMap(\.payloadString).filter { seen.insert($0).inserted }
        return content
    }

    /// Areas worth hiding before sharing, in image pixels with the origin at the top left.
    @concurrent
    static func sensitiveAreas(in image: CGImage, kinds: Set<SensitiveKind>) async throws -> [CGRect] {
        let size = CGSize(width: image.width, height: image.height)
        var areas: [CGRect] = []

        if kinds.contains(.faces) {
            let faces = try await DetectFaceRectanglesRequest().perform(on: image)
            areas += faces.map { face in
                let rect = face.boundingBox.toImageCoordinates(size, origin: .upperLeft)
                // Faces read better hidden with a little room around them.
                return rect.insetBy(dx: -rect.width * 0.15, dy: -rect.height * 0.2)
            }
        }

        if kinds.contains(.personal) || kinds.contains(.allText) {
            var request = RecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.automaticallyDetectsLanguage = true
            for observation in try await request.perform(on: image) {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let lineRect = observation.boundingBox.toImageCoordinates(size, origin: .upperLeft)
                if kinds.contains(.allText) {
                    areas.append(lineRect)
                    continue
                }
                for range in sensitiveRanges(in: candidate.string) {
                    let rect = candidate.boundingBox(for: range)
                        .map { $0.boundingBox.toImageCoordinates(size, origin: .upperLeft) } ?? lineRect
                    areas.append(rect)
                }
            }
        }

        let bounds = CGRect(origin: .zero, size: size)
        return areas
            .map { $0.insetBy(dx: -3, dy: -3).intersection(bounds).integral }
            .filter { !$0.isNull && $0.width > 2 && $0.height > 2 }
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
}
