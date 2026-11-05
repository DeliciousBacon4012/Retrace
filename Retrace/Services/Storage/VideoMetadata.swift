import AVFoundation
import Foundation
import OSLog

/// Finds and removes descriptive metadata in finished movies, such as a location, the
/// device or app that made them, or a title.
///
/// Movies Retrace writes normally carry none, so the check costs only a read of the
/// movie's header. Only when it finds something is the movie rewritten, copying its
/// samples without re-encoding.
nonisolated enum VideoMetadata {
    /// The identifiers of every metadata item in the movie and in its tracks.
    static func items(in url: URL) async throws -> [String] {
        let asset = AVURLAsset(url: url)
        var found = try await asset.load(.metadata).map(name(of:))
        for track in try await asset.load(.tracks) {
            found += try await track.load(.metadata).map(name(of:))
        }
        return found
    }

    enum RemovalError: LocalizedError {
        case metadataRemains([String])
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .metadataRemains(let identifiers):
                String(localized: "Some video metadata could not be removed: \(identifiers.joined(separator: ", ")).")
            case .failed(let reason):
                String(localized: "Video metadata could not be removed: \(reason)")
            }
        }
    }

    /// Rewrites the movie at `url` without metadata if it has any. The original is replaced
    /// only after the new copy is complete, so a failure leaves the recording as it was.
    static func removeAll(from url: URL) async throws {
        do {
            let found = try await items(in: url)
            guard !found.isEmpty else { return }
            try await rewrite(url)
            let left = try await items(in: url)
            guard left.isEmpty else {
                Log.capture.error("A movie still has metadata: \(left.joined(separator: ", "), privacy: .public)")
                throw RemovalError.metadataRemains(left)
            }
            Log.capture.info("Removed \(found.count) metadata items from a movie")
        } catch let error as RemovalError {
            throw error
        } catch {
            Log.capture.error("Couldn't remove a movie's metadata: \(error.localizedDescription, privacy: .public)")
            throw RemovalError.failed(error.localizedDescription)
        }
    }

    /// Copies the movie's samples, unchanged, into a new movie that has no metadata at the
    /// movie or track level, then swaps it in. An export session can't do this: it carries
    /// the source's software, device and date items through even with its sharing filter.
    private static func rewrite(_ url: URL) async throws {
        let fileManager = FileManager.default
        // A folder on the same volume, so the finished copy can replace the original in place.
        let folder = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
        defer { try? fileManager.removeItem(at: folder) }
        let copy = folder.appendingPathComponent(url.lastPathComponent)

        let source = AVMovie(url: url)
        let duration = try await source.load(.duration)
        let movie = AVMutableMovie()
        movie.defaultMediaDataStorage = AVMediaDataStorage(url: copy)
        try movie.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: .zero, copySampleData: true)
        movie.metadata = []
        for track in movie.tracks {
            track.metadata = []
        }
        // The samples are already in `copy`; this adds the movie header after them.
        try movie.writeHeader(to: copy, fileType: fileType(for: url), options: .addMovieHeaderToDestination)
        _ = try fileManager.replaceItemAt(url, withItemAt: copy)
    }

    private static func fileType(for url: URL) -> AVFileType {
        url.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
    }

    private static func name(of item: AVMetadataItem) -> String {
        if let identifier = item.identifier { return identifier.rawValue }
        return item.key.map { String(describing: $0) } ?? "unknown"
    }
}
