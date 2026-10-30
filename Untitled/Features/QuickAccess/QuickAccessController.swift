import AppKit
import SwiftUI

/// Shows a floating thumbnail for each new capture, stacked in the corner chosen in Settings.
final class QuickAccessController {
    private struct Entry {
        let id: UUID
        let panel: NSPanel
        var autoClose: Task<Void, Never>?
    }

    /// At most this many thumbnails are shown; older ones close first.
    private let maximumVisible = 5
    private let spacing: CGFloat = 10
    private let margin: CGFloat = 20

    private let settings: SettingsStore
    private let clipboard: any ClipboardWriting
    private var entries: [Entry] = []

    init(settings: SettingsStore, clipboard: any ClipboardWriting) {
        self.settings = settings
        self.clipboard = clipboard
    }

    func show(_ capture: CapturedImage) {
        let view = QuickAccessThumbnail(
            capture: capture,
            onCopy: { [weak self] in self?.clipboard.copy(capture.nsImage) },
            onClose: { [weak self] in self?.dismiss(capture.id) }
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.setFrameSize(hostingView.fittingSize)

        let panel = ThumbnailPanel(contentRect: CGRect(origin: .zero, size: hostingView.fittingSize))
        panel.contentView = hostingView

        var entry = Entry(id: capture.id, panel: panel)
        let seconds = settings.overlayAutoCloseSeconds
        if seconds > 0 {
            entry.autoClose = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                self?.dismiss(capture.id)
            }
        }

        entries.append(entry)
        while entries.count > maximumVisible, let oldest = entries.first {
            dismiss(oldest.id)
        }
        layout()
        panel.orderFrontRegardless()
    }

    func dismiss(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries.remove(at: index)
        entry.autoClose?.cancel()
        entry.panel.orderOut(nil)
        layout()
    }

    /// Stacks the panels away from the chosen corner, newest nearest the corner.
    private func layout() {
        guard let screen = NSScreen.underPointer ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        let corner = settings.overlayCorner
        var offset: CGFloat = 0

        for entry in entries.reversed() {
            let size = entry.panel.frame.size
            let x: CGFloat = switch corner {
            case .bottomLeft, .topLeft: area.minX + margin
            case .bottomRight, .topRight: area.maxX - margin - size.width
            }
            let y: CGFloat = switch corner {
            case .bottomLeft, .bottomRight: area.minY + margin + offset
            case .topLeft, .topRight: area.maxY - margin - size.height - offset
            }
            entry.panel.setFrameOrigin(CGPoint(x: x, y: y))
            offset += size.height + spacing
        }
    }
}

/// A floating panel that never takes focus away from the app you're working in.
private final class ThumbnailPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
}
