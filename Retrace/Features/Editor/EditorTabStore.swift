import CoreGraphics
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

/// Keeps the Editor tab's image and its edits, undo history included, in Application Support,
/// so quitting or restarting the Mac picks up exactly where it was.
nonisolated enum EditorTabStore {
    struct Saved: Codable, Sendable {
        var fileURL: URL?
        var preferredSaveFolderURL: URL?
        var scale: CGFloat
        var edits: EditorDocument.SavedEdits
    }

    private static let log = Logger(subsystem: Log.subsystem, category: "editorTab")
    private static let queue = DispatchQueue(label: "Retrace.EditorTabStore", qos: .utility)

    private static var folder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: Bundle.main.bundleIdentifier ?? "Retrace", directoryHint: .isDirectory)
            .appending(path: "Editor Tab", directoryHint: .isDirectory)
    }

    /// The image is written once per session, the edits whenever they change.
    static func save(_ saved: Saved, image: CGImage?) {
        guard let folder else { return }
        queue.async {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                if let image {
                    let url = folder.appending(path: "image.png")
                    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
                    CGImageDestinationAddImage(destination, image, nil)
                    CGImageDestinationFinalize(destination)
                }
                try JSONEncoder().encode(saved).write(to: folder.appending(path: "edits.json"), options: .atomic)
            } catch {
                log.error("Couldn't keep the Editor tab: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func clear() {
        guard let folder else { return }
        queue.async { try? FileManager.default.removeItem(at: folder) }
    }

    /// What was open in the Editor tab last time, if anything.
    static func load() async -> (Saved, CGImage)? {
        guard let folder else { return nil }
        return await withCheckedContinuation { continuation in
            queue.async {
                guard let data = try? Data(contentsOf: folder.appending(path: "edits.json")),
                      let saved = try? JSONDecoder().decode(Saved.self, from: data),
                      let source = CGImageSourceCreateWithURL(folder.appending(path: "image.png") as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (saved, image))
            }
        }
    }
}
