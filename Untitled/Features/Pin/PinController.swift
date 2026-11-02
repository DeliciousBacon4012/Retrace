import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Keeps screenshots floating above every window, like a sticky note you can resize.
final class PinController {
    private let clipboard: any ClipboardWriting
    private var panels: [PinPanel] = []

    /// Opens a pinned image in the editor.
    var onEdit: ((CapturedImage) -> Void)?

    init(clipboard: any ClipboardWriting) {
        self.clipboard = clipboard
    }

    func pin(_ capture: CapturedImage) {
        let panel = PinPanel(capture: capture)
        let view = PinnedImageView(
            capture: capture,
            copy: { [weak self] in self?.clipboard.copy(capture.nsImage) },
            edit: { [weak self, weak panel] in
                self?.onEdit?(capture)
                if let panel { self?.close(panel) }
            },
            close: { [weak self, weak panel] in
                if let panel { self?.close(panel) }
            },
            setOpacity: { [weak panel] value in panel?.alphaValue = value }
        )
        panel.setHostedContent(NSHostingView(rootView: view))
        panels.append(panel)

        // Start at the image's real size near the pointer, but never larger than most of the screen.
        let screen = NSScreen.underPointer ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        var size = capture.pointSize
        let limit = CGSize(width: visible.width * 0.6, height: visible.height * 0.6)
        let fit = min(limit.width / max(size.width, 1), limit.height / max(size.height, 1), 1)
        size = CGSize(width: max(size.width * fit, 80), height: max(size.height * fit, 60))
        let pointer = NSEvent.mouseLocation
        var origin = CGPoint(x: pointer.x - size.width / 2, y: pointer.y - size.height / 2)
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        panel.setFrame(CGRect(origin: origin, size: size), display: false)
        panel.contentAspectRatio = size

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            panel.animator().alphaValue = 1
        }
    }

    /// Asks for an image file and pins it.
    func pinFromFile() {
        let open = NSOpenPanel()
        open.allowedContentTypes = [.image]
        open.allowsMultipleSelection = true
        NSApp.activate()
        guard open.runModal() == .OK else { return }
        for url in open.urls {
            guard let image = NSImage(contentsOf: url), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let scale = image.size.width > 0 ? max(CGFloat(cgImage.width) / image.size.width, 1) : 1
            pin(CapturedImage(image: cgImage, scale: scale, date: .now, fileURL: url))
        }
    }

    private func close(_ panel: PinPanel) {
        panels.removeAll { $0 === panel }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }
}

/// A borderless, resizable window that floats above everything and keeps the image's shape.
private final class PinPanel: NSPanel {
    init(capture: CapturedImage) {
        super.init(
            contentRect: CGRect(origin: .zero, size: capture.pointSize),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        minSize = CGSize(width: 60, height: 40)
    }

    override var canBecomeKey: Bool { true }
}

private struct PinnedImageView: View {
    let capture: CapturedImage
    let copy: () -> Void
    let edit: () -> Void
    let close: () -> Void
    let setOpacity: (CGFloat) -> Void

    @State private var isHovering = false

    var body: some View {
        Image(nsImage: capture.nsImage)
            .resizable()
            .interpolation(.high)
            .clipShape(.rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(isHovering ? 0.35 : 0.12), lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                if isHovering {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .padding(6)
                    .transition(.scale(0.6).combined(with: .opacity))
                    .help("Unpin")
                    .accessibilityLabel("Unpin")
                }
            }
            .onHover { hovering in
                withAnimation(.response) { isHovering = hovering }
            }
            .onTapGesture(count: 2, perform: edit)
            .contextMenu {
                Button("Copy", systemImage: "doc.on.doc", action: copy)
                Button("Open in Editor", systemImage: "pencil.tip.crop.circle", action: edit)
                Menu("Opacity") {
                    ForEach([1.0, 0.75, 0.5, 0.25], id: \.self) { value in
                        Button(value.formatted(.percent)) { setOpacity(value) }
                    }
                }
                Divider()
                Button("Unpin", systemImage: "pin.slash", action: close)
            }
            .accessibilityLabel("Pinned screenshot")
    }
}
