import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// How an image is written out: format, compression, size, color, and metadata.
nonisolated struct ExportOptions: Hashable, Sendable {
    var format: ImageFormat
    /// Compression quality for lossy formats, from 0 to 1.
    var quality: Double = 0.85
    /// The output size as a percentage of the original pixels.
    var scalePercent: Double = 100
    /// For lossy formats, the largest file allowed. Quality is lowered until it fits.
    var maximumBytes: Int?
    /// Leaves out EXIF, GPS, and device details.
    var stripsMetadata = true
    /// Converts wide-gamut captures to sRGB so colors look the same everywhere.
    var convertsToSRGB = true
}

/// Turns images into file data with ImageIO, entirely on-device.
nonisolated enum ImageEncoder {
    enum EncodingError: LocalizedError {
        case unsupportedFormat
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat: String(localized: "This Mac can't write that image format.")
            case .encodingFailed: String(localized: "The image couldn't be encoded.")
            }
        }
    }

    /// Encodes with default quality and no resizing.
    static func data(for image: CGImage, format: ImageFormat) throws -> Data {
        try data(for: image, options: ExportOptions(format: format, quality: 0.9))
    }

    /// Encodes `image` following `options`. `pointScale` is the capture's pixels per point,
    /// written as the file's resolution so it opens at the right size.
    static func data(for image: CGImage, options: ExportOptions, pointScale: CGFloat = 1) throws -> Data {
        let prepared = prepare(image, options: options)
        let factor = max(options.scalePercent, 1) / 100
        let dpi = 72 * max(pointScale * factor, 1)

        guard options.format.isLossy, let limit = options.maximumBytes else {
            return try encode(prepared, options: options, quality: options.quality, dpi: dpi)
        }

        // Find the highest quality that still fits under the limit.
        var best = try encode(prepared, options: options, quality: 0.05, dpi: dpi)
        guard best.count <= limit else { return best }
        var low = 0.05
        var high = min(max(options.quality, 0.05), 1)
        let top = try encode(prepared, options: options, quality: high, dpi: dpi)
        if top.count <= limit { return top }
        for _ in 0..<7 {
            let middle = (low + high) / 2
            let candidate = try encode(prepared, options: options, quality: middle, dpi: dpi)
            if candidate.count <= limit {
                best = candidate
                low = middle
            } else {
                high = middle
            }
        }
        return best
    }

    /// Encodes off the main thread, for live size estimates and exports.
    @concurrent
    static func encodeInBackground(_ image: CGImage, options: ExportOptions, pointScale: CGFloat) async throws -> Data {
        try data(for: image, options: options, pointScale: pointScale)
    }

    /// The pixel size an image will have after resizing.
    static func outputSize(of image: CGImage, options: ExportOptions) -> CGSize {
        let factor = min(max(options.scalePercent, 1), 100) / 100
        return CGSize(width: max((CGFloat(image.width) * factor).rounded(), 1), height: max((CGFloat(image.height) * factor).rounded(), 1))
    }

    private static func prepare(_ image: CGImage, options: ExportOptions) -> CGImage {
        let size = outputSize(of: image, options: options)
        let resizes = Int(size.width) != image.width || Int(size.height) != image.height
        let target = targetColorSpace(for: image, options: options)
        guard resizes || target != nil else { return image }
        return redrawn(image, size: size, in: target ?? image.colorSpace) ?? image
    }

    /// The color space to convert to, or nil to keep the image's own.
    ///
    /// Captures arrive tagged with the display's own ICC profile, whose name can identify the
    /// screen. Converting to sRGB, or to the standard Display P3 profile when stripping
    /// metadata, leaves a generic profile in the file instead.
    private static func targetColorSpace(for image: CGImage, options: ExportOptions) -> CGColorSpace? {
        let current = image.colorSpace?.name as String?
        if options.convertsToSRGB {
            return current == CGColorSpace.sRGB as String ? nil : CGColorSpace(name: CGColorSpace.sRGB)
        }
        if options.stripsMetadata, !genericSpaceNames.contains(current ?? "") {
            return CGColorSpace(name: CGColorSpace.displayP3)
        }
        return nil
    }

    private static let genericSpaceNames: Set<String> = [
        CGColorSpace.sRGB as String,
        CGColorSpace.displayP3 as String,
        CGColorSpace.extendedSRGB as String,
        CGColorSpace.extendedDisplayP3 as String,
        CGColorSpace.linearSRGB as String,
        CGColorSpace.genericGrayGamma2_2 as String,
    ]

    /// Draws the image into a new bitmap. Drawing into a context with another color space
    /// converts the colors, unlike `copy(colorSpace:)`, which only relabels them.
    private static func redrawn(_ image: CGImage, size: CGSize, in space: CGColorSpace?) -> CGImage? {
        // Gray or indexed sources draw into sRGB, since the bitmap below is always RGBA.
        guard let space = space.flatMap({ $0.model == .rgb ? $0 : nil }) ?? CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }

    private static func encode(_ image: CGImage, options: ExportOptions, quality: Double, dpi: CGFloat) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, options.format.utType.identifier as CFString, 1, nil) else {
            throw EncodingError.unsupportedFormat
        }
        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        if options.format.isLossy {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        if !options.stripsMetadata {
            // EXIF and TIFF dates use "2026:10:31 15:24:00" in local time, not ISO 8601.
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            let date = formatter.string(from: .now)
            properties[kCGImagePropertyTIFFDictionary] = [
                kCGImagePropertyTIFFSoftware: "Untitled",
                kCGImagePropertyTIFFDateTime: date,
            ]
            properties[kCGImagePropertyExifDictionary] = [
                kCGImagePropertyExifDateTimeOriginal: date,
            ]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw EncodingError.encodingFailed
        }
        return data as Data
    }
}

extension ImageFormat {
    nonisolated var utType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        case .avif: UTType("public.avif") ?? .heic
        case .tiff: .tiff
        case .gif: .gif
        }
    }

    nonisolated var isLossy: Bool {
        self == .jpeg || self == .heic || self == .avif
    }

    nonisolated var fileExtension: String {
        utType.preferredFilenameExtension ?? rawValue
    }
}
