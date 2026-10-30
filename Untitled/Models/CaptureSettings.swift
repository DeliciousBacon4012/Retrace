import Foundation

/// Image file formats a capture can be saved as.
nonisolated enum ImageFormat: String, CaseIterable, Identifiable, Sendable {
    case png
    case jpeg
    case heic
    case tiff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        case .tiff: "TIFF"
        }
    }
}

/// Video codecs a recording can be encoded with.
nonisolated enum VideoCodec: String, CaseIterable, Identifiable, Sendable {
    case h264
    case hevc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .h264: "H.264"
        case .hevc: "HEVC"
        }
    }
}

/// Where the Quick Access overlay appears.
nonisolated enum OverlayCorner: String, CaseIterable, Identifiable, Sendable {
    case bottomLeft
    case bottomRight
    case topLeft
    case topRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bottomLeft: String(localized: "Bottom left")
        case .bottomRight: String(localized: "Bottom right")
        case .topLeft: String(localized: "Top left")
        case .topRight: String(localized: "Top right")
        }
    }
}
