import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Editor tab: pick up a recent image, open another, or start a blank canvas.
/// Each image opens in its own editor window.
struct EditorLandingView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var isImporting = false
    @State private var isDropTargeted = false
    @State private var errorMessage: String?

    private static let recentLimit = 12

    var body: some View {
        VStack(spacing: Design.spacingXL) {
            if recentImages.isEmpty {
                ContentUnavailableView {
                    Label("Start Editing", systemImage: "photo.badge.plus")
                } description: {
                    Text("Open an image, create a canvas, or drag an image here.")
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                recents
            }

            HStack(spacing: Design.spacingM) {
                Button("Open Image…", systemImage: "photo") { isImporting = true }
                Button("New Canvas", systemImage: "rectangle.dashed") { createCanvas() }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Label("You can also drop an image anywhere here", systemImage: "arrow.down.doc")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: Design.radiusL)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(Design.spacingS)
                    .allowsHitTesting(false)
            }
        }
        .animation(.response, value: isDropTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, Self.isImage(url) else {
                NSSound.beep()
                return false
            }
            dependencies.editor.open(fileAt: url)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                guard Self.isImage(url) else {
                    errorMessage = String(localized: "Choose an image file to open in the editor.")
                    return
                }
                dependencies.editor.open(fileAt: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .alert("Couldn't Open Image", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: Design.spacingM) {
            Text("Continue Editing")
                .font(.title2.weight(.semibold))
                .padding(.horizontal, Design.spacingXL)

            ScrollView(.horizontal) {
                LazyHStack(spacing: Design.spacingL) {
                    ForEach(recentImages) { item in
                        RecentImageCard(item: item) {
                            dependencies.editor.open(fileAt: item.url)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, Design.spacingXL)
                .padding(.vertical, Design.spacingS)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.never)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
    }

    private var recentImages: [LibraryItem] {
        Array(
            dependencies.library.items
                .filter { $0.kind == .image }
                .sorted { $0.modified > $1.modified }
                .prefix(Self.recentLimit)
        )
    }

    private func createCanvas() {
        let size = CGSize(width: 1920, height: 1080)
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = makeCanvasImage(in: context, size: size) else {
            errorMessage = String(localized: "A new canvas couldn't be created. Try again.")
            return
        }
        dependencies.editor.open(CapturedImage(image: image, scale: 1, date: .now))
    }

    private func makeCanvasImage(in context: CGContext, size: CGSize) -> CGImage? {
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        return context.makeImage()
    }
}

/// One recent image. Lifts slightly under the pointer; a click opens it.
private struct RecentImageCard: View {
    let item: LibraryItem
    let open: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: Design.spacingS) {
                FileThumbnail(url: item.url, version: item.modified)
                    .frame(width: 220, height: 140)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: Design.radiusM))
                    .clipShape(.rect(cornerRadius: Design.radiusM))
                    .scaleEffect(isHovered && !reduceMotion ? 1.03 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(item.modified.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Design.spacingXS)
            }
            .frame(width: 220, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.response, value: isHovered)
        .accessibilityLabel("Open \(item.name) in the editor")
    }
}
