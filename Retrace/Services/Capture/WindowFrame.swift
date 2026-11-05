import CoreGraphics
import Foundation

/// What fills the space around a window capture.
nonisolated enum WindowBackground: String, CaseIterable, Identifiable, Sendable {
    case transparent
    case white
    case gray
    case black

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transparent: String(localized: "None")
        case .white: String(localized: "White")
        case .gray: String(localized: "Gray")
        case .black: String(localized: "Black")
        }
    }

    var color: CGColor? {
        switch self {
        case .transparent: nil
        case .white: CGColor(gray: 1, alpha: 1)
        case .gray: CGColor(gray: 0.86, alpha: 1)
        case .black: CGColor(gray: 0.08, alpha: 1)
        }
    }
}

/// Puts a window capture on a canvas with padding, a soft shadow, and a background,
/// the way the window looks on screen. All sizes are in points and scale with the capture.
nonisolated enum WindowFrame {
    /// Space a shadow needs around the window so it isn't cut off, in points.
    static let shadowMargin: CGFloat = 36

    struct Style: Equatable, Sendable {
        var padding: CGFloat
        var shadow: Bool
        var background: WindowBackground

        /// True when the window comes out exactly as captured.
        var isPlain: Bool { padding == 0 && !shadow && background == .transparent }
    }

    static func decorate(_ window: CGImage, scale: CGFloat, style: Style) -> CGImage {
        guard !style.isPlain else { return window }

        let margin = max(style.padding, style.shadow ? shadowMargin : 0) * scale
        let width = window.width + Int((margin * 2).rounded())
        let height = window.height + Int((margin * 2).rounded())
        guard
            let space = window.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return window }

        context.interpolationQuality = .none
        if let fill = style.background.color {
            context.setFillColor(fill)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }

        let frame = CGRect(x: margin, y: margin, width: CGFloat(window.width), height: CGFloat(window.height))
        if style.shadow {
            // Close to the system's active-window shadow: a wide soft spread, offset downward.
            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: -12 * scale),
                blur: 30 * scale,
                color: CGColor(gray: 0, alpha: 0.45)
            )
            context.draw(window, in: frame)
            context.restoreGState()
        } else {
            context.draw(window, in: frame)
        }
        return context.makeImage() ?? window
    }
}
