import AppKit
import QuickLookThumbnailing
import SwiftUI

/// A Quick Look thumbnail of a file, loaded in the background and cached.
struct FileThumbnail: View {
    let url: URL
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
        .task(id: url) {
            let loaded = await ThumbnailCache.shared.thumbnail(for: url, size: maximumSize, scale: displayScale)
            withAnimation(.easeOut(duration: 0.15)) { image = loaded }
        }
        .accessibilityHidden(true)
    }
}

/// Keeps recent thumbnails in memory so scrolling back doesn't regenerate them.
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 400
        return cache
    }()

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
        cache.setObject(image, forKey: key)
        return image
    }
}
