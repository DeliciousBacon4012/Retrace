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
    /// history can leave out what Retrace copied itself.
    var lastWriteChangeCount: Int? { get }
}

final class SystemClipboard: ClipboardWriting {
    /// The pasteboard only holds a weak reference to whoever supplies data later.
    private var imageProvider: AnyObject?
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
        // One item carrying both the file and its pixels, so apps paste it once. The pixels are
        // only decoded if an app actually asks for them.
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        let provider = FileImageProvider(url: url)
        item.setDataProvider(provider, forTypes: [.tiff])
        imageProvider = provider
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

/// Supplies a file's pixels to the pasteboard on demand.
private final class FileImageProvider: NSObject, NSPasteboardItemDataProvider {
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .tiff, let tiff = NSImage(contentsOf: url)?.tiffRepresentation else { return }
        item.setData(tiff, forType: .tiff)
    }
}
