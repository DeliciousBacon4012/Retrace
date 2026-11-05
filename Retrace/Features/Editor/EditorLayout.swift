import AppKit
import SwiftUI

/// Where the editor's inspector sits. Remembered between editors and launches.
nonisolated enum InspectorPlacement: String, CaseIterable, Identifiable, Sendable {
    case right
    case left
    /// Over the image, wherever it was dropped.
    case floating
    /// In a window of its own.
    case window

    static let storageKey = "editorInspectorPlacement"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .right: String(localized: "Docked Right")
        case .left: String(localized: "Docked Left")
        case .floating: String(localized: "Floating")
        case .window: String(localized: "Separate Window")
        }
    }
}

/// The three dots on top of the inspector: drag them to float the inspector, drop it at
/// either side to dock it, or drop it outside the window to give it a window of its own.
struct InspectorGrip: View {
    @Binding var placement: InspectorPlacement
    let onDrag: (DragGesture.Value) -> Void
    let onDrop: (DragGesture.Value) -> Void

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .contentShape(.rect)
            .pointerStyle(.grabIdle)
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named(EditorLayout.space))
                    .onChanged(onDrag)
                    .onEnded(onDrop)
            )
            .contextMenu {
                Picker("Inspector", selection: $placement) {
                    ForEach(InspectorPlacement.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            }
            .help("Drag to move the inspector. Drop it at a side to dock it, or outside the window to give it its own.")
            .accessibilityLabel("Move Inspector")
    }
}

nonisolated enum EditorLayout {
    /// The coordinate space of the editor's content, for dragging the inspector.
    static let space = "editorContent"
}

/// The inspector in a window of its own: a standard utility panel that floats above the
/// editor while Retrace is in front. Closing it docks the inspector again.
final class InspectorWindowController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    /// Called when the person closes the panel.
    var onClose: (() -> Void)?

    var isShown: Bool { panel != nil }

    /// Shows the panel, with its top left corner near `point` (screen coordinates) if given.
    func show(
        document: EditorDocument,
        near point: NSPoint?,
        extractedText: String?,
        onCopyText: @escaping (String) -> Void,
        onCopyImage: @escaping () -> Void,
        imageTransfer: @escaping () -> EditorImageTransfer,
        onLiftSubject: @escaping () -> Void,
        isLiftingSubject: Bool
    ) {
        let panel = panel ?? makePanel(
            document: document,
            extractedText: extractedText,
            onCopyText: onCopyText,
            onCopyImage: onCopyImage,
            imageTransfer: imageTransfer,
            onLiftSubject: onLiftSubject,
            isLiftingSubject: isLiftingSubject
        )
        self.panel = panel
        panel.contentView = NSHostingView(rootView: EditorInspector(
            document: document,
            chrome: .window,
            extractedText: extractedText,
            onCopyText: onCopyText,
            onCopyImage: onCopyImage,
            imageTransfer: imageTransfer,
            onLiftSubject: onLiftSubject,
            isLiftingSubject: isLiftingSubject
        ))
        if let point {
            panel.setFrameTopLeftPoint(NSPoint(x: point.x - EditorInspector.width / 2, y: point.y + 12))
        }
        panel.orderFront(nil)
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        panel.delegate = nil
        panel.close()
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        onClose?()
    }

    private func makePanel(
        document: EditorDocument,
        extractedText: String?,
        onCopyText: @escaping (String) -> Void,
        onCopyImage: @escaping () -> Void,
        imageTransfer: @escaping () -> EditorImageTransfer,
        onLiftSubject: @escaping () -> Void,
        isLiftingSubject: Bool
    ) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: EditorInspector.width, height: 560),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = String(localized: "Inspector")
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.contentMinSize = NSSize(width: EditorInspector.width, height: 240)
        panel.contentMaxSize = NSSize(width: EditorInspector.width, height: .greatestFiniteMagnitude)
        panel.contentView = NSHostingView(rootView: EditorInspector(
            document: document,
            chrome: .window,
            extractedText: extractedText,
            onCopyText: onCopyText,
            onCopyImage: onCopyImage,
            imageTransfer: imageTransfer,
            onLiftSubject: onLiftSubject,
            isLiftingSubject: isLiftingSubject
        ))
        panel.delegate = self
        panel.center()
        return panel
    }
}
