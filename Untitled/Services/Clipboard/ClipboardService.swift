import AppKit
import OSLog

/// Puts captures on the clipboard.
protocol ClipboardWriting: AnyObject {
    func copy(_ image: NSImage)
    /// Copies a saved file so it pastes as a file in Finder and as its contents in most apps.
    func copyFile(at url: URL)
    /// Copies several saved files, which paste as files in Finder.
    func copyFiles(at urls: [URL])
    func copy(text: String)
    /// True while the clipboard still holds an image this app put there, untouched since.
    var holdsOurImage: Bool { get }
    /// The clipboard's change count right after this app last wrote to it, so clipboard
    /// history can leave out what retrace copied itself.
    var lastWriteChangeCount: Int? { get }
}

final class SystemClipboard: ClipboardWriting {
    /// The clipboard's change count right after this app last copied an image.
    private var imageChangeCount: Int?
    private(set) var lastWriteChangeCount: Int?

    var holdsOurImage: Bool {
        imageChangeCount == NSPasteboard.general.changeCount
    }

    func copy(_ image: NSImage) {
        write([image])
        imageChangeCount = NSPasteboard.general.changeCount
    }

    func copyFile(at url: URL) {
        // One item carrying both the file and its pixels, so apps paste it once.
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        if let image = NSImage(contentsOf: url), let tiff = image.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        write([item])
        imageChangeCount = NSPasteboard.general.changeCount
    }

    func copyFiles(at urls: [URL]) {
        write(urls.map { $0 as NSURL })
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
        lastWriteChangeCount = pasteboard.changeCount
    }
}

#if DEBUG
/// A stand-in for previews and tests.
final class PreviewClipboard: ClipboardWriting {
    var holdsOurImage: Bool { false }
    var lastWriteChangeCount: Int? { nil }
    func copy(_ image: NSImage) {}
    func copyFile(at url: URL) {}
    func copyFiles(at urls: [URL]) {}
    func copy(text: String) {}
}
#endif
