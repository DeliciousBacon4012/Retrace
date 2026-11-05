import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Editor tab is a simple entry point into the existing document editor.
struct EditorLandingView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 28) {
            if let recentImage {
                HStack(spacing: 24) {
                    FileThumbnail(url: recentImage.url)
                        .frame(width: 280, height: 180)
                        .clipShape(.rect(cornerRadius: 16))
                        .accessibilityLabel("Most recent image: \(recentImage.name)")

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Continue Editing")
                            .font(.title2.weight(.semibold))
                        Text(recentImage.name)
                            .lineLimit(1)
                        Text(recentImage.modified.formatted(date: .abbreviated, time: .shortened))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Open in Editor", systemImage: "pencil.and.outline") {
                            dependencies.editor.open(fileAt: recentImage.url)
                        }
                        .buttonStyle(.glass)
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: 310, alignment: .leading)
                }
                .frame(maxWidth: 680, alignment: .center)
            } else {
                ContentUnavailableView {
                    Label("Start Editing", systemImage: "photo.badge.plus")
                } description: {
                    Text("Open an image, create a canvas, or drag an image here.")
                }
            }

            HStack(spacing: 12) {
                Button("Open Image…", systemImage: "photo") {
                    isImporting = true
                }
                .buttonStyle(.glass)

                Button("New Canvas", systemImage: "rectangle.dashed") {
                    createCanvas()
                }
                .buttonStyle(.glass)
            }

            if recentImage != nil {
                Label("Or drop an image here to open it in the editor", systemImage: "arrow.down.doc")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, Self.isImage(url) else {
                NSSound.beep()
                return false
            }
            dependencies.editor.open(fileAt: url)
            return true
        }
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

    private static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
    }

    private var recentImage: LibraryItem? {
        dependencies.library.items
            .filter { $0.kind == .image }
            .max { $0.modified < $1.modified }
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
