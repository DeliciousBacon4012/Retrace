import AppKit
import SwiftUI

/// The floating thumbnail shown after a capture. Hover for actions, drag it into any app,
/// or double-click to open it.
struct QuickAccessThumbnail: View {
    let capture: CapturedImage
    let onCopy: () -> Void
    let onAnnotate: () -> Void
    let onClose: () -> Void

    @State private var isShown = false
    @State private var isHovering = false
    @State private var didCopy = false

    private var thumbnailSize: CGSize {
        let maximum: CGFloat = 220
        let size = capture.pointSize
        guard size.width > 0, size.height > 0 else { return CGSize(width: maximum, height: maximum * 0.6) }
        let ratio = min(maximum / size.width, maximum / size.height)
        return CGSize(width: max(size.width * ratio, 120), height: max(size.height * ratio, 70))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: capture.nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                .clipShape(.rect(cornerRadius: Design.radiusS))
                .overlay {
                    if isHovering {
                        hoverActions
                            .transition(.opacity)
                    }
                }
                .padding(5)
                .glassEffect(.regular, in: .rect(cornerRadius: Design.radiusM))

            if isHovering {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .offset(x: -6, y: -6)
                .transition(.scale(0.5).combined(with: .opacity))
                .help("Close")
                .accessibilityLabel("Close")
            }
        }
        .padding(14)
        .scaleEffect(isShown ? 1 : 0.86, anchor: .bottomTrailing)
        .offset(x: isShown ? 0 : 60)
        .opacity(isShown ? 1 : 0)
        .onAppear {
            withAnimation(.pop) { isShown = true }
        }
        .onHover { hovering in
            withAnimation(.response) { isHovering = hovering }
        }
        .onDrag {
            if let url = capture.fileURL {
                return NSItemProvider(object: url as NSURL)
            }
            return NSItemProvider(object: capture.nsImage)
        }
        .onTapGesture(count: 2) {
            if let url = capture.fileURL {
                NSWorkspace.shared.open(url)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(capture.isVideo ? "Recording" : "Screenshot")
    }

    private var hoverActions: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.25))
            GlassEffectContainer(spacing: 6) {
                VStack(spacing: 6) {
                    if !capture.isVideo {
                        Button("Annotate", systemImage: "pencil.tip.crop.circle", action: onAnnotate)
                    }
                    Button(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc") {
                        onCopy()
                        withAnimation(.response) { didCopy = true }
                    }
                    .contentTransition(.symbolEffect(.replace))
                    if let url = capture.fileURL {
                        Button("Show in Finder", systemImage: "folder") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                }
                .controlSize(.small)
                .buttonStyle(.glass)
            }
        }
        .clipShape(.rect(cornerRadius: Design.radiusS))
    }
}
