import AppKit

/// Opens Library items in other apps, each in a window of its own: text in the text app from
/// Settings, images in Preview, and movies in QuickTime Player.
struct LibraryOpener {
    let texts: [String]
    let images: [URL]
    let movies: [URL]

    private static let preview = "com.apple.Preview"
    private static let quickTime = "com.apple.QuickTimePlayerX"

    init(_ items: [RecentItem], clipboardImageURL: (ClipboardEntry) -> URL?) {
        var texts: [String] = []
        var images: [URL] = []
        var movies: [URL] = []
        for item in items {
            switch item {
            case .file(let file):
                if file.kind == .video { movies.append(file.url) } else { images.append(file.url) }
            case .text(let snippet):
                texts.append(snippet.text)
            case .clipboard(let entry):
                if let url = clipboardImageURL(entry) {
                    images.append(url)
                } else if let text = entry.text {
                    texts.append(text)
                }
            }
        }
        self.texts = texts
        self.images = images
        self.movies = movies
    }

    /// More than one kind, so "Open All" sends each to its own app.
    var isMixed: Bool {
        [!texts.isEmpty, !images.isEmpty, !movies.isEmpty].filter { $0 }.count > 1
    }

    func openTexts(in app: PlainTextApp) {
        texts.forEach { PlainTextOpener.open($0, in: app) }
    }

    func openImagesInPreview() {
        Self.openSeparately(images, withApp: Self.preview)
    }

    func openMoviesInQuickTime() {
        Self.openSeparately(movies, withApp: Self.quickTime)
    }

    func openAll(textApp: PlainTextApp) {
        openTexts(in: textApp)
        openImagesInPreview()
        openMoviesInQuickTime()
    }

    /// One at a time, so the app gives each file its own window instead of grouping them.
    private static func openSeparately(_ urls: [URL], withApp bundleID: String) {
        guard !urls.isEmpty, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            urls.forEach { NSWorkspace.shared.open($0) }
            return
        }
        Task {
            for url in urls {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = url == urls.last
                _ = try? await NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration)
            }
        }
    }
}
