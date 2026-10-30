import AppKit
import OSLog

/// Puts captures on the clipboard.
protocol ClipboardWriting: AnyObject {
    func copy(_ image: NSImage)
}

final class SystemClipboard: ClipboardWriting {
    func copy(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !pasteboard.writeObjects([image]) {
            Log.capture.error("Could not write the image to the clipboard")
        }
    }
}

#if DEBUG
/// A stand-in for previews and tests.
final class PreviewClipboard: ClipboardWriting {
    func copy(_ image: NSImage) {}
}
#endif
