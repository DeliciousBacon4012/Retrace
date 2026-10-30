import AppKit
import SwiftUI

/// The floating thumbnail shown after a capture. Hover for actions, drag it into any app,
/// or double-click to open it.
struct QuickAccessThumbnail: View {
    let capture: CapturedImage
    let onCopy: () -> Void
    let onAnnotate: () -> Void
    let onClose: () -> Void

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
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    if isHovering {
                        hoverActions
                            .transition(.opacity)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
                }

            if isHovering {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .glassCircle()
                .padding(6)
                .help("Close")
                .accessibilityLabel("Close")
            }
        }
        .padding(12)
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
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
        .accessibilityLabel("Screenshot")
    }

    private var hoverActions: some View {
        ZStack {
            Color.black.opacity(0.3)
            VStack(spacing: 8) {
                Button("Annotate", action: onAnnotate)
                Button(didCopy ? "Copied" : "Copy") {
                    onCopy()
                    didCopy = true
                }
                if let url = capture.fileURL {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
            .controlSize(.small)
            .glassButtons()
        }
    }
}

private extension View {
    @ViewBuilder
    func glassButtons() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func glassCircle() -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.interactive(), in: .circle)
        } else {
            background(.regularMaterial, in: Circle())
        }
    }
}
