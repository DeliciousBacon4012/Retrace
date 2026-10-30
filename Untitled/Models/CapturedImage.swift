import AppKit

/// A finished screenshot, ready for the after-capture actions.
struct CapturedImage: Identifiable {
    let id = UUID()
    let image: CGImage
    /// Pixels per point the image was captured at, such as 2 on a Retina display.
    let scale: CGFloat
    let date: Date
    /// Where the image was saved, if it was saved.
    var fileURL: URL?

    /// The image's size in points, so it displays at its on-screen size.
    var pointSize: NSSize {
        NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
    }

    var nsImage: NSImage {
        NSImage(cgImage: image, size: pointSize)
    }
}
