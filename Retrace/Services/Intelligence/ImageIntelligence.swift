import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Which part of an image Smart Crop looks for.
nonisolated enum SmartCropMode: String, CaseIterable, Identifiable, Sendable {
    /// Where a person's eye goes first.
    case attention
    /// The distinct objects in the frame.
    case objects
    /// A page, card, or receipt.
    case document

    static let storageKey = "smartCropMode"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .attention: String(localized: "Attention")
        case .objects: String(localized: "Objects")
        case .document: String(localized: "Document")
        }
    }
}

/// How Vision reads text.
nonisolated enum TextRecognitionSpeed: String, CaseIterable, Identifiable, Sendable {
    case accurate
    case fast

    static let storageKey = "textRecognitionSpeed"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .accurate: String(localized: "Accurate")
        case .fast: String(localized: "Fast")
        }
    }

    static var current: TextRecognitionSpeed {
        UserDefaults.standard.string(forKey: storageKey).flatMap(Self.init(rawValue:)) ?? .accurate
    }
}

/// What Vision recognizes in a picture.
nonisolated struct ImageLabel: Codable, Hashable, Identifiable, Sendable {
    var name: String
    var confidence: Float
    var id: String { name }

    /// Vision names its categories like `outdoor_structure`.
    var title: String {
        name.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

/// Apple's on-device image understanding. Nothing here leaves the Mac.
nonisolated enum ImageIntelligence {
    private static let queue = DispatchQueue(label: "Retrace.ImageIntelligence", qos: .utility)

    /// What's in the picture, most certain first. Vision's list has over a thousand categories;
    /// a category only counts when Vision would rarely be wrong to report it.
    static func labels(in image: CGImage, limit: Int = 8) async throws -> [ImageLabel] {
        try await run {
            let request = VNClassifyImageRequest()
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            return (request.results ?? [])
                .filter { $0.hasMinimumPrecision(0.7, forRecall: 0.05) }
                .prefix(limit)
                .map { ImageLabel(name: $0.identifier, confidence: $0.confidence) }
        }
    }

    /// A fingerprint of how the picture looks, for finding others like it.
    static func featurePrint(of image: CGImage) async throws -> Data? {
        try await run {
            let request = VNGenerateImageFeaturePrintRequest()
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            guard let print = request.results?.first else { return nil }
            return try NSKeyedArchiver.archivedData(withRootObject: print, requiringSecureCoding: true)
        }
    }

    /// How different two fingerprints are. Smaller is more alike.
    static func distance(between first: Data, and second: Data) -> Float? {
        guard let a = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: first),
              let b = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: second)
        else { return nil }
        var distance: Float = 0
        guard (try? a.computeDistance(&distance, to: b)) != nil else { return nil }
        return distance
    }

    /// Suggests a crop, in top-left image pixels. Returns nil when nothing useful is found.
    static func suggestedCrop(in image: CGImage, mode: SmartCropMode) async throws -> CGRect? {
        let size = CGSize(width: image.width, height: image.height)
        let box: CGRect? = try await run {
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            switch mode {
            case .attention:
                let request = VNGenerateAttentionBasedSaliencyImageRequest()
                try handler.perform([request])
                return strongestObject(in: request.results?.first)
            case .objects:
                let request = VNGenerateObjectnessBasedSaliencyImageRequest()
                try handler.perform([request])
                return allObjects(in: request.results?.first)
            case .document:
                let request = VNDetectDocumentSegmentationRequest()
                try handler.perform([request])
                return request.results?.first?.boundingBox
            }
        }
        guard let box else { return nil }
        return cropRect(forVisionBox: box, in: size, padding: mode == .document ? 0 : 0.18)
    }

    /// Vision's normalized, bottom-left box as a padded, top-left pixel rectangle.
    static func cropRect(forVisionBox box: CGRect, in size: CGSize, padding: CGFloat) -> CGRect? {
        let bounds = CGRect(origin: .zero, size: size)
        let subject = CGRect(
            x: box.minX * size.width,
            y: (1 - box.maxY) * size.height,
            width: box.width * size.width,
            height: box.height * size.height
        )
        guard subject.width.isFinite, subject.height.isFinite, subject.width > 0, subject.height > 0 else { return nil }
        let padded = subject
            .insetBy(dx: -subject.width * padding, dy: -subject.height * padding)
            .intersection(bounds)
            .integral
        guard padded.width >= 8, padded.height >= 8,
              padded.width < bounds.width * 0.98 || padded.height < bounds.height * 0.98
        else { return nil }
        return padded
    }

    /// Reads a file at a reduced size, which is all recognition needs and far less memory.
    static func downsampledImage(at url: URL, maxPixelSize: Int = 1024) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary)
    }

    private static func strongestObject(in observation: VNSaliencyImageObservation?) -> CGRect? {
        observation?.salientObjects?.max { $0.confidence < $1.confidence }?.boundingBox
    }

    private static func allObjects(in observation: VNSaliencyImageObservation?) -> CGRect? {
        guard let objects = observation?.salientObjects, let first = objects.first else { return nil }
        return objects.dropFirst().reduce(first.boundingBox) { $0.union($1.boundingBox) }
    }

    private static func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }
}
