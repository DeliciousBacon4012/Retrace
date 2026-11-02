import AppKit
import QuickLookThumbnailing
import SwiftUI

/// A Quick Look thumbnail of a file, loaded in the background and cached.
struct FileThumbnail: View {
    let url: URL
    /// When the file last changed. A new value reloads the thumbnail, such as after an edit.
    var version: Date?
    var maximumSize = CGSize(width: 320, height: 220)

    @Environment(\.displayScale) private var displayScale
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .transition(.opacity)
            } else {
                Image(systemName: "photo")
                    .font(.title)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: LoadKey(url: url, version: version)) {
            let loaded = await ThumbnailCache.shared.thumbnail(for: url, size: maximumSize, scale: displayScale)
            withAnimation(.easeOut(duration: 0.15)) { image = loaded }
        }
        .accessibilityHidden(true)
    }

    private struct LoadKey: Equatable {
        let url: URL
        let version: Date?
    }
}

/// Keeps recent thumbnails in memory so scrolling back doesn't regenerate them, up to a
/// memory limit set in Settings › Advanced. The oldest go first when it's reached.
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 400
        cache.totalCostLimit = 64 * 1_048_576
        return cache
    }()

    func setMemoryLimit(megabytes: Int) {
        cache.totalCostLimit = megabytes * 1_048_576
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    func thumbnail(for url: URL, size: CGSize, scale: CGFloat) async -> NSImage? {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let key = "\(url.path(percentEncoded: false))|\(modified?.timeIntervalSince1970 ?? 0)|\(Int(size.width))x\(Int(size.height))@\(scale)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .thumbnail)
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        let image = representation.nsImage
        let bytes = representation.cgImage.bytesPerRow * representation.cgImage.height
        cache.setObject(image, forKey: key, cost: bytes)
        return image
    }
}
