import AVFoundation
import VideoToolbox

/// The color space a recording captures in.
nonisolated enum VideoColor: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case sRGB
    case displayP3
    case rec709

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: String(localized: "Automatic")
        case .sRGB: "sRGB"
        case .displayP3: "Display P3"
        case .rec709: "Rec. 709"
        }
    }

    var colorSpaceName: CFString? {
        switch self {
        case .automatic: nil
        case .sRGB: CGColorSpace.sRGB
        case .displayP3: CGColorSpace.displayP3
        case .rec709: CGColorSpace.itur_709
        }
    }
}

/// How hard a movie is compressed, in bits for each pixel of each frame. Screen content
/// compresses far better than camera footage, so these sit low.
nonisolated enum VideoQuality: String, CaseIterable, Identifiable, Sendable {
    /// Whatever ScreenCaptureKit writes, with no second pass.
    case original
    case high
    case balanced
    case small

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: String(localized: "Original")
        case .high: String(localized: "High")
        case .balanced: String(localized: "Balanced")
        case .small: String(localized: "Small File")
        }
    }

    var bitsPerPixel: Double? {
        switch self {
        case .original: nil
        case .high: 0.2
        case .balanced: 0.1
        case .small: 0.05
        }
    }

    /// Replays are written live, so they have no "original" to keep.
    static let replayChoices: [VideoQuality] = [.high, .balanced, .small]

    func bitRate(width: Int, height: Int, framesPerSecond: Double) -> Int {
        let pixelsPerSecond = Double(width * height) * framesPerSecond
        return max(2_000_000, Int(pixelsPerSecond * (bitsPerPixel ?? 0.1)))
    }
}

/// Which encoder compresses video that Retrace writes itself.
nonisolated enum VideoEncoderChoice: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case hardware
    case software

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: String(localized: "Automatic")
        case .hardware: String(localized: "Hardware Only")
        case .software: String(localized: "Software")
        }
    }

    /// The value for `AVVideoEncoderSpecificationKey`, if this choice needs one.
    var specification: [String: Bool]? {
        switch self {
        case .automatic:
            nil
        case .hardware:
            [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true]
        case .software:
            [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: false]
        }
    }
}

/// How cursor motion blur is drawn.
nonisolated enum CursorBlurMode: String, CaseIterable, Identifiable, Sendable {
    /// One directional blur along the cursor's direction of travel.
    case fast
    /// Many copies along its true path, so curves and shape changes stay right.
    case quality

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: String(localized: "Fast")
        case .quality: String(localized: "Quality")
        }
    }
}

/// How the editor previews blur. Exports always use the full-quality blur.
nonisolated enum EditorBlurQuality: String, CaseIterable, Identifiable, Sendable {
    case fast
    case quality

    static let storageKey = "editorBlurQuality"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: String(localized: "Fast")
        case .quality: String(localized: "Quality")
        }
    }

    static var current: EditorBlurQuality {
        UserDefaults.standard.string(forKey: storageKey).flatMap(Self.init(rawValue:)) ?? .quality
    }
}

/// Starting points for every recording setting at once. Changing any one setting by hand
/// makes the preset read as Custom.
nonisolated enum RecordingPreset: String, CaseIterable, Identifiable, Sendable {
    case performance
    case balanced
    case highQuality
    case studio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .performance: String(localized: "Better Performance")
        case .balanced: String(localized: "Balanced")
        case .highQuality: String(localized: "High Quality")
        case .studio: String(localized: "Studio")
        }
    }

    var codec: VideoCodec {
        switch self {
        case .performance, .balanced, .highQuality: .hevc
        case .studio: .proRes422HQ
        }
    }

    var framesPerSecond: Int {
        switch self {
        case .performance: 30
        default: 60
        }
    }

    var quality: VideoQuality {
        switch self {
        case .performance: .small
        case .balanced, .studio: .original
        case .highQuality: .high
        }
    }

    var encoder: VideoEncoderChoice {
        switch self {
        case .performance, .highQuality: .hardware
        case .balanced, .studio: .automatic
        }
    }

    var color: VideoColor {
        switch self {
        case .performance, .balanced: .automatic
        case .highQuality, .studio: .displayP3
        }
    }

    var queueDepth: Int {
        switch self {
        case .performance: 4
        case .balanced: 6
        case .highQuality, .studio: 8
        }
    }
}
