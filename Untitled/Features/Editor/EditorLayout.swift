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

/// Where the editor's tools sit: in the window's toolbar, or on a glass bar along an edge.
nonisolated enum EditorToolbarPosition: String, CaseIterable, Identifiable, Sendable {
    case top
    case bottom
    case left
    case right

    static let storageKey = "editorToolbarPosition"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .top: String(localized: "Top")
        case .bottom: String(localized: "Bottom")
        case .left: String(localized: "Left")
        case .right: String(localized: "Right")
        }
    }

    var symbolName: String {
        switch self {
        case .top: "rectangle.tophalf.inset.filled"
        case .bottom: "rectangle.bottomhalf.inset.filled"
        case .left: "rectangle.lefthalf.inset.filled"
        case .right: "rectangle.righthalf.inset.filled"
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

/// The tools on a glass bar along one edge of the editor, for when they aren't in the
/// window's toolbar. The chosen tool's highlight slides from tool to tool.
struct EditorToolPalette: View {
    @Bindable var document: EditorDocument
    let axis: Axis
    let symbol: (EditorTool) -> String
    @Binding var position: EditorToolbarPosition
    @Namespace private var highlight

    static let thickness: CGFloat = 40

    var body: some View {
        let layout = axis == .vertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
        GlassEffectContainer {
            layout {
                ForEach(EditorTool.allCases) { tool in
                    button(for: tool)
                }
            }
            .padding(4)
            .glassEffect(.regular, in: .capsule)
        }
        .animation(.smooth(duration: 0.25), value: document.tool)
        .contextMenu {
            Picker("Toolbar Position", selection: $position) {
                ForEach(EditorToolbarPosition.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
            }
            .pickerStyle(.inline)
        }
    }

    private func button(for tool: EditorTool) -> some View {
        let isSelected = tool == document.tool
        return Button {
            document.tool = tool
        } label: {
            Image(systemName: symbol(tool))
                .font(.system(size: 14, weight: .medium))
                .frame(width: Self.thickness - 8, height: Self.thickness - 8)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background {
                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .matchedGeometryEffect(id: "tool", in: highlight)
                    }
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help("\(tool.title) (\(String(tool.key).uppercased()))")
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

nonisolated enum EditorLayout {
    /// The coordinate space of the editor's content, for dragging the inspector.
    static let space = "editorContent"
}

/// The inspector in a window of its own: a standard utility panel that floats above the
/// editor while Untitled is in front. Closing it docks the inspector again.
final class InspectorWindowController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    /// Called when the person closes the panel.
    var onClose: (() -> Void)?

    var isShown: Bool { panel != nil }

    /// Shows the panel, with its top left corner near `point` (screen coordinates) if given.
    func show(document: EditorDocument, near point: NSPoint?) {
        let panel = panel ?? makePanel(document: document)
        self.panel = panel
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

    private func makePanel(document: EditorDocument) -> NSPanel {
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
        panel.contentView = NSHostingView(rootView: EditorInspector(document: document, chrome: .window))
        panel.delegate = self
        panel.center()
        return panel
    }
}
