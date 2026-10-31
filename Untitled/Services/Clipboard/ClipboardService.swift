import AppKit
import OSLog

/// Puts captures on the clipboard.
protocol ClipboardWriting: AnyObject {
    func copy(_ image: NSImage)
    /// Copies a saved file so it pastes as a file in Finder and as its contents in most apps.
    func copyFile(at url: URL)
    func copy(text: String)
}

final class SystemClipboard: ClipboardWriting {
    func copy(_ image: NSImage) {
        write([image])
    }

    func copyFile(at url: URL) {
        // One item carrying both the file and its pixels, so apps paste it once.
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        if let image = NSImage(contentsOf: url), let tiff = image.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        write([item])
    }

    func copy(text: String) {
        write([text as NSString])
    }

    private func write(_ objects: [any NSPasteboardWriting]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !pasteboard.writeObjects(objects) {
            Log.capture.error("Could not write to the clipboard")
        }
    }
}

#if DEBUG
/// A stand-in for previews and tests.
final class PreviewClipboard: ClipboardWriting {
    func copy(_ image: NSImage) {}
    func copyFile(at url: URL) {}
    func copy(text: String) {}
}
#endif
