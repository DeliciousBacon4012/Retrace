import CoreGraphics
import CoreTransferable
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A lazily encoded PNG drag payload. The editor provides its rendered image only when a drag starts.
nonisolated struct EditorImageTransfer: Transferable, Sendable {
    enum ExportError: LocalizedError {
        case imageUnavailable
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .imageUnavailable: String(localized: "The edited image is not available to drag.")
            case .encodingFailed: String(localized: "The edited image could not be prepared for dragging.")
            }
        }
    }

    let image: CGImage?

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { transfer in
            try transfer.pngData()
        }
    }

    func pngData() throws -> Data {
        guard let image else { throw ExportError.imageUnavailable }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ExportError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ExportError.encodingFailed }
        return data as Data
    }
}
