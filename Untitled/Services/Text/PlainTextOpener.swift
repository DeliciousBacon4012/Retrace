import AppKit
import OSLog
import UniformTypeIdentifiers

/// The app captured text opens in.
nonisolated enum PlainTextApp: String, CaseIterable, Identifiable, Sendable {
    case textEdit
    /// Whatever app opens plain text files on this Mac.
    case defaultApp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .textEdit: "TextEdit"
        case .defaultApp: String(localized: "Default app for text files")
        }
    }
}

/// Opens captured text as a `.txt` file. TextEdit always opens those as plain text, never
/// rich text, so nothing about the text changes on the way.
enum PlainTextOpener {
    /// The name of the app `open(_:in:)` uses, such as "TextEdit", for a button title.
    static func appName(for app: PlainTextApp) -> String {
        guard let url = applicationURL(for: app) else { return "TextEdit" }
        return FileManager.default.displayName(atPath: url.path(percentEncoded: false))
            .replacingOccurrences(of: ".app", with: "")
    }

    static func open(_ text: String, in app: PlainTextApp) {
        do {
            let url = try write(text)
            if let appURL = applicationURL(for: app) {
                NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(url)
            }
        } catch {
            Log.capture.error("Couldn't write captured text to a file: \(error.localizedDescription, privacy: .public)")
            ErrorPresenter.present(error)
        }
    }

    private static func applicationURL(for app: PlainTextApp) -> URL? {
        switch app {
        case .textEdit:
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit")
        case .defaultApp:
            NSWorkspace.shared.urlForApplication(toOpen: .plainText)
        }
    }

    /// Writes the text to a new file in a temporary folder, named after the time, so each
    /// snippet opens as its own document.
    private static func write(_ text: String) throws -> URL {
        let fileManager = FileManager.default
        let folder = fileManager.temporaryDirectory.appendingPathComponent("Captured Text", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stamp = formatter.string(from: .now)
        var url = folder.appendingPathComponent(String(localized: "Text \(stamp)")).appendingPathExtension("txt")
        var number = 2
        while fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            url = folder.appendingPathComponent(String(localized: "Text \(stamp) \(number)")).appendingPathExtension("txt")
            number += 1
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
