import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns a captured image into file data.
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

    static func data(for image: CGImage, format: ImageFormat) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, format.utType.identifier as CFString, 1, nil) else {
            throw EncodingError.unsupportedFormat
        }
        var properties: [CFString: Any] = [:]
        if format.isLossy {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.9
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
        case .tiff: .tiff
        }
    }

    nonisolated var isLossy: Bool {
        self == .jpeg || self == .heic
    }

    nonisolated var fileExtension: String {
        utType.preferredFilenameExtension ?? rawValue
    }
}
