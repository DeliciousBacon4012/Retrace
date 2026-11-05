import AppKit

/// A finished screenshot, ready for the after-capture actions.
struct CapturedImage: Identifiable {
    // A screenshot, or the first frame of a recording.
    let id = UUID()
    let image: CGImage
    /// Pixels per point the image was captured at, such as 2 on a Retina display.
    let scale: CGFloat
    let date: Date
    /// Where the image was saved, if it was saved.
    var fileURL: URL?
    /// The destination chosen for this capture, used if it is saved later from Quick Access.
    var preferredSaveFolderURL: URL?
    /// True when this is a recording's poster frame rather than a screenshot.
    var isVideo = false
    /// The screenshot mode, if this image came from a Retrace capture action.
    var captureSource: CaptureSource?

    /// The image's size in points, so it displays at its on-screen size.
    var pointSize: NSSize {
        NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
    }

    var nsImage: NSImage {
        NSImage(cgImage: image, size: pointSize)
    }
}
