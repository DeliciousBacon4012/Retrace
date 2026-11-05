import AppKit
import SwiftUI

/// Every setting for the selected mark, or for the next mark the current tool draws, in a
/// grouped set of standard controls on a floating panel of system Liquid Glass.
/// Changes apply live and become the tool's style for next time.
struct EditorInspector: View {
    /// How the inspector is framed.
    enum Chrome {
        /// A glass panel over the editor, with a grip to drag it by, as tall as its content
        /// up to `maxHeight`.
        case panel(grip: InspectorGrip, maxHeight: CGFloat)
        /// Filling a window of its own, which has a title bar to drag.
        case window
    }

    @Bindable var document: EditorDocument
    let chrome: Chrome
    let onLiftSubject: () -> Void
    let isLiftingSubject: Bool

    nonisolated static let width: CGFloat = 280
    private static let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
    private static let gripHeight: CGFloat = 22

    var body: some View {
        switch chrome {
        case .panel(let grip, let maxHeight):
            VStack(spacing: 0) {
                grip
                InspectorPanelLayout(maxHeight: max(maxHeight - Self.gripHeight, 120)) {
                    ViewThatFits(in: .vertical) {
                        content
                            .fixedSize(horizontal: false, vertical: true)
                        ScrollView {
                            content
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .scrollEdgeEffectStyle(.soft, for: .vertical)
                        .contentMargins(.vertical, 12, for: .scrollIndicators)
                    }
                }
            }
            .frame(width: Self.width)
            .clipShape(Self.shape)
            .glassEffect(.regular, in: Self.shape)
            .animation(.smooth(duration: 0.16), value: document.inspectedTool)
        case .window:
            ScrollView {
                content
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: Self.width, maxWidth: Self.width, maxHeight: .infinity)
            .scrollEdgeEffectStyle(.soft, for: .vertical)
        }
    }

    private var content: some View {
        let tool = document.inspectedTool

        return VStack(alignment: .leading, spacing: 14) {
            InspectorGroup {
                InspectorHeader(tool: tool, selectionCount: document.selectedIDs.count, isMixed: document.selectionIsMixed)
            }

            switch tool {
            case _ where document.selectionIsMixed:
                InspectorGroup {
                    Text("These marks are different kinds. Select marks of one kind to change their style.")
                        .foregroundStyle(.secondary)
                }
            case .select:
                InspectorGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Click a mark to change it. Drag its handles to reshape it, or drag the mark to move it. Drag across marks, Shift-click, or press ⌘A to select several.")
                            .foregroundStyle(.secondary)

                        Button(action: onLiftSubject) {
                            if isLiftingSubject {
                                HStack(spacing: 7) {
                                    ProgressView().controlSize(.small)
                                    Text("Finding subject…")
                                }
                            } else {
                                Label("Copy Subject", systemImage: "person.crop.rectangle")
                            }
                        }
                        .buttonStyle(.glass)
                        .disabled(isLiftingSubject)
                        .help("Copy the foreground as a transparent image using on-device Vision. Existing redactions are included.")
                    }
                }
            case .crop:
                CropSection(document: document)
            default:
                VariantSection(document: document, tool: tool)
                ColorSection(document: document, tool: tool)
                ToolSection(document: document, tool: tool)
                if tool != .highlighter, tool != .redact, tool != .spotlight {
                    EffectsSection(document: document)
                }
                if tool == .redact, !document.hasSelection {
                    AutoRedactSection(document: document)
                }
            }

            if document.hasSelection {
                ArrangeSection(document: document)
            }

            if tool.draws, !document.selectionIsMixed {
                InspectorGroup {
                    Button("Reset to Default Style", systemImage: "arrow.counterclockwise") {
                        withAnimation(.response) { document.resetStyle() }
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .controlSize(.small)
        .animation(.smooth(duration: 0.22), value: tool)
    }
}

/// Measures the chosen content at its natural height first. Only if it exceeds the available
/// room does the layout propose a height limit, letting ViewThatFits choose its scroll fallback.
private struct InspectorPanelLayout: Layout {
    let maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let width = proposal.width ?? EditorInspector.width
        let naturalSize = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
        guard naturalSize.height > maxHeight else {
            return CGSize(width: width, height: naturalSize.height)
        }

        let scrollSize = subview.sizeThatFits(ProposedViewSize(width: width, height: maxHeight))
        return CGSize(width: width, height: min(scrollSize.height, maxHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let naturalSize = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        let height = min(naturalSize.height, maxHeight)
        subview.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: height)
        )
    }
}

/// A compact native control group sized to its contents inside the floating inspector.
private struct InspectorGroup<Content: View, Footer: View>: View {
    let title: LocalizedStringKey?
    let content: Content
    let footer: Footer

    init(_ title: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) where Footer == EmptyView {
        self.title = title
        self.content = content()
        footer = EmptyView()
    }

    init(
        _ title: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            content

            footer
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InspectorHeader: View {
    let tool: EditorTool
    let selectionCount: Int
    let isMixed: Bool

    private var caption: LocalizedStringKey {
        switch selectionCount {
        case 0: tool.draws ? "Next mark" : "Tool"
        case 1: "Selected mark"
        default: "\(selectionCount) marks selected"
        }
    }

    var body: some View {
        LabeledContent {
            if !isMixed {
                Text(String(tool.key).uppercased())
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .help("Press \(String(tool.key).uppercased()) to pick this tool")
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(isMixed ? String(localized: "Selection") : tool.title)
                        .font(.headline)
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: tool.symbolName)
                    .foregroundStyle(.tint)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
    }
}

/// The variant pickers, like Blur, Pixelate or Solid.
private struct VariantSection: View {
    @Bindable var document: EditorDocument
    let tool: EditorTool

    var body: some View {
        switch tool {
        case .arrow:
            InspectorGroup {
                GlassSegmentedPicker("Type", selection: $document.style.route, options: ArrowRoute.allCases, name: \.title) { Image(systemName: $0.symbolName) }
                Picker("Start", selection: $document.style.startHead) {
                    ForEach(ArrowHead.allCases) { Text($0.title).tag($0) }
                }
                Picker("End", selection: $document.style.endHead) {
                    ForEach(ArrowHead.allCases) { Text($0.title).tag($0) }
                }
                Button("Swap Ends", systemImage: "arrow.left.arrow.right") {
                    let start = document.style.startHead
                    document.style.startHead = document.style.endHead
                    document.style.endHead = start
                }
                .buttonStyle(.glass)
            }
        case .shape:
            InspectorGroup {
                GlassSegmentedPicker("Shape", selection: $document.style.shape, options: ShapeKind.allCases, name: \.title) { Image(systemName: $0.symbolName) }
                GlassSegmentedPicker("Fill", selection: $document.style.fill, options: ShapeFill.allCases, name: \.title) { Text($0.title) }
            }
        case .redact:
            InspectorGroup {
                GlassSegmentedPicker("Type", selection: $document.style.redaction, options: Redaction.allCases, name: \.title) { Text($0.title) }
                GlassSegmentedPicker("Shape", selection: $document.style.shape, options: ShapeKind.allCases, name: \.title) { Image(systemName: $0.symbolName) }
            }
        case .spotlight:
            InspectorGroup {
                GlassSegmentedPicker("Shape", selection: $document.style.shape, options: ShapeKind.allCases, name: \.title) { Image(systemName: $0.symbolName) }
            }
        case .text:
            InspectorGroup {
                GlassSegmentedPicker("Style", selection: $document.style.textStyle, options: TextStyle.allCases, name: \.title) { Text($0.title) }
                Picker("Font", selection: $document.style.font) {
                    ForEach(TextFont.allCases) { Text($0.title).tag($0) }
                }
                Picker("Weight", selection: $document.style.weight) {
                    ForEach(TextWeight.allCases) { Text($0.title).tag($0) }
                }
            }
        case .counter:
            InspectorGroup {
                GlassSegmentedPicker("Style", selection: $document.style.counterStyle, options: CounterStyle.allCases, name: \.title) { Text($0.title) }
            }
        default:
            EmptyView()
        }
    }
}

/// Color swatches, a custom color, and opacity.
private struct ColorSection: View {
    @Bindable var document: EditorDocument
    let tool: EditorTool
    @AppStorage(EditorPalette.storageKey) private var palette: EditorPalette = .pastel
    @AppStorage(EditorPalette.customColorsStorageKey) private var customPaletteData = EditorPalette.defaultCustomColorsData
    @State private var editsCustomPalette = false

    var body: some View {
        Group {
            if tool != .spotlight, tool != .redact || document.style.redaction == .solid {
                InspectorGroup("Color") {
                    let customColors = EditorPalette.customColors(from: customPaletteData)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 8) {
                        ForEach(Array(zip(palette.colors(custom: customColors), palette.names).enumerated()), id: \.offset) { index, swatch in
                            Swatch(color: swatch.0, name: swatch.1, isSelected: swatch.0.sameHue(as: document.style.color)) {
                                withAnimation(.response) { document.style.color = swatch.0 }
                            }
                            .help(helpText(name: swatch.1, index: index))
                        }
                    }
                    .padding(.vertical, 2)
                    ColorPicker("Custom", selection: customColor, supportsOpacity: false)
                    Picker("Palette", selection: $palette) {
                        ForEach(EditorPalette.allCases) { Text($0.title).tag($0) }
                    }
                    if palette == .custom {
                        Button("Edit Custom Palette…", systemImage: "slider.horizontal.3") {
                            editsCustomPalette = true
                        }
                    }
                    if tool != .redact {
                        ValueSlider("Opacity", value: $document.style.opacity, in: 0.1...1, format: .percent)
                    }
                }
            }
        }
        .sheet(isPresented: $editsCustomPalette) {
            EditorPaletteEditor(encodedColors: $customPaletteData)
        }
    }

    private func helpText(name: String, index: Int) -> String {
        guard let digit = EditorPalette.digit(forSwatchAt: index) else { return name }
        return "\(name) (\(digit))"
    }

    private var customColor: Binding<Color> {
        Binding {
            document.style.color.swiftUIColor
        } set: { newValue in
            guard let resolved = NSColor(newValue).usingColorSpace(.sRGB) else { return }
            document.style.color = RGBAColor(
                red: Double(resolved.redComponent),
                green: Double(resolved.greenComponent),
                blue: Double(resolved.blueComponent)
            )
        }
    }
}

private struct Swatch: View {
    let color: RGBAColor
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.swiftUIColor)
                .overlay { Circle().strokeBorder(.separator, lineWidth: 1) }
                .padding(isSelected ? 3 : 0)
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                            .transition(.scale(1.3).combined(with: .opacity))
                    }
                }
                .frame(width: 24, height: 24)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The settings that only make sense for one tool.
private struct ToolSection: View {
    @Bindable var document: EditorDocument
    @AppStorage(EditorDocument.highlighterSnapsKey) private var snapsToText = true
    let tool: EditorTool

    var body: some View {
        switch tool {
        case .arrow:
            InspectorGroup("Line") {
                ValueSlider("Thickness", value: points(\.lineWidth), in: 1...30, unit: "pt")
                ValueSlider("Head Size", value: $document.style.headScale, in: 0.5...2.5, format: .percent)
                Toggle("Tapered", isOn: $document.style.tapered)
                Toggle("Dashed", isOn: $document.style.dashed)
            }
        case .shape:
            InspectorGroup("Border") {
                ValueSlider("Thickness", value: points(\.lineWidth), in: 0...30, unit: "pt")
                if document.style.shape == .rectangle {
                    ValueSlider("Roundness", value: points(\.cornerRadius), in: 0...80, unit: "pt")
                }
                Toggle("Dashed", isOn: $document.style.dashed)
            }
        case .pen:
            InspectorGroup("Stroke") {
                ValueSlider("Thickness", value: points(\.lineWidth), in: 1...30, unit: "pt")
                Toggle("Dashed", isOn: $document.style.dashed)
            }
        case .highlighter:
            InspectorGroup("Stroke") {
                ValueSlider("Thickness", value: points(\.lineWidth), in: 4...60, unit: "pt")
                Toggle("Snap to text", isOn: $snapsToText)
            } footer: {
                if snapsToText {
                    Text("Drag along a line of text to cover its words neatly. Hold Shift and drag a box to highlight every line inside it. Hold Option to draw freely.")
                } else {
                    Text("Hold Shift while dragging for a perfectly straight stroke.")
                }
            }
            .onChange(of: snapsToText) {
                if snapsToText { document.prepareTextLines() }
            }
        case .text:
            InspectorGroup("Size") {
                ValueSlider("Size", value: points(\.fontSize), in: 8...120, unit: "pt")
            }
        case .counter:
            InspectorGroup("Size") {
                ValueSlider("Size", value: points(\.fontSize), in: 10...64, unit: "pt")
            }
        case .spotlight:
            InspectorGroup("Everything Else") {
                ValueSlider("Dim", value: $document.style.dim, in: 0...1, format: .percent)
                ValueSlider("Fade", value: $document.style.fade, in: 0...1, format: .percent)
                ValueSlider("Blur", value: $document.style.blur, in: 0...1, format: .percent)
                if document.style.shape == .rectangle {
                    ValueSlider("Roundness", value: points(\.cornerRadius), in: 0...80, unit: "pt")
                }
            } footer: {
                Text("Draw several spotlights to light up more than one area. The newest one sets how the rest of the image looks.")
            }
        case .redact:
            if document.style.redaction != .solid || document.style.shape == .rectangle {
                InspectorGroup("Amount") {
                    if document.style.redaction != .solid {
                        ValueSlider("Strength", value: $document.style.strength, in: 0...1, format: .percent)
                    }
                    if document.style.shape == .rectangle {
                        ValueSlider("Roundness", value: points(\.cornerRadius), in: 0...80, unit: "pt")
                    }
                } footer: {
                    if document.style.redaction != .solid {
                        Text("Blur and pixelate can sometimes be partly undone. Use Solid for passwords, numbers and anything private.")
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    /// A binding that shows a pixel size in points.
    private func points(_ keyPath: WritableKeyPath<MarkStyle, CGFloat>) -> Binding<Double> {
        document.pointBinding(keyPath)
    }
}

/// Drop shadow.
private struct EffectsSection: View {
    @Bindable var document: EditorDocument

    var body: some View {
        InspectorGroup("Shadow") {
            Toggle("Shadow", isOn: $document.style.shadow.animation(.response))
            if document.style.shadow {
                ValueSlider("Softness", value: document.pointBinding(\.shadowRadius), in: 0...30, unit: "pt")
                ValueSlider("Darkness", value: $document.style.shadowOpacity, in: 0.05...0.8, format: .percent)
            }
        }
    }
}

/// Aspect presets for the crop tool.
private struct CropSection: View {
    let document: EditorDocument
    @State private var isFindingSubject = false
    @State private var message: String?

    var body: some View {
        InspectorGroup("Crop") {
            Picker("Aspect Ratio", selection: Binding(get: { document.cropAspect }, set: { document.setCropAspect($0) })) {
                Text(CropAspect.free.title).tag(CropAspect.free)
                Text(CropAspect.original.title).tag(CropAspect.original)
                Divider()
                ForEach(CropAspect.allCases.filter { $0 != .free && $0 != .original }) { Text($0.title).tag($0) }
            }
            Button {
                Task { await suggestCrop() }
            } label: {
                if isFindingSubject {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text("Finding subject…")
                    }
                } else {
                    Label("Smart Crop", systemImage: "viewfinder")
                }
            }
            .buttonStyle(.glass)
            .disabled(isFindingSubject)
            .help("Suggest a crop around the main subject using on-device Vision.")

            HStack {
                Button("Reset") { document.resetCrop() }
                    .buttonStyle(.glass)
                    .disabled(!document.isCropped)
                Spacer()
                Button("Crop", systemImage: "checkmark") { document.commitCrop() }
                    .buttonStyle(.glassProminent)
            }
        } footer: {
            Text(message ?? String(localized: "Drag the handles or move the box. Smart Crop uses on-device Vision; review its suggestion before applying. Press Return to crop, or Esc to cancel."))
        }
    }

    @MainActor
    private func suggestCrop() async {
        guard !isFindingSubject else { return }
        isFindingSubject = true
        defer { isFindingSubject = false }
        do {
            guard let suggestion = try await TextRecognizer.attentionCrop(in: document.image),
                  document.applySuggestedCrop(suggestion)
            else {
                message = String(localized: "No clear subject was found. Adjust the crop manually.")
                return
            }
            message = String(localized: "Crop suggested. Review the framing before applying.")
        } catch {
            message = error.localizedDescription
        }
    }
}

/// Order, duplicate, and delete for the selected marks.
private struct ArrangeSection: View {
    let document: EditorDocument

    var body: some View {
        InspectorGroup("Arrange") {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    Button("Duplicate", systemImage: "plus.square.on.square") { document.duplicateSelection() }
                        .help("Duplicate (⌘D)")
                    Button("Bring to Front", systemImage: "square.3.layers.3d.top.filled") { document.bringSelectionToFront() }
                        .help("Bring to Front (⌘])")
                    Button("Send to Back", systemImage: "square.3.layers.3d.bottom.filled") { document.sendSelectionToBack() }
                        .help("Send to Back (⌘[)")
                    Spacer()
                    Button("Delete", systemImage: "trash", role: .destructive) { document.deleteSelection() }
                        .help("Delete (⌫)")
                }
                .buttonStyle(.glass)
                .labelStyle(.iconOnly)
            }
        }
    }
}

/// A slider with its value in fixed-width digits beside it, so the value changing never
/// resizes the row or nudges the slider under the pointer.
struct ValueSlider: View {
    enum Format {
        case number(unit: String)
        case percent
    }

    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: Format

    init(_ title: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>, unit: String) {
        self.title = title
        _value = value
        self.range = range
        format = .number(unit: unit)
    }

    init(_ title: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>, format: Format) {
        self.title = title
        _value = value
        self.range = range
        self.format = format
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Slider(value: $value, in: range) { Text(title) }
                    .labelsHidden()
                Text(formatted)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var formatted: String {
        switch format {
        case .percent: value.formatted(.percent.precision(.fractionLength(0)))
        case .number(let unit): "\(Int(value.rounded())) \(unit)"
        }
    }
}

/// Finds personal details, faces, or all text on device and covers them in one step.
private struct AutoRedactSection: View {
    let document: EditorDocument

    @State private var running: SensitiveKind?
    @State private var result: String?

    var body: some View {
        InspectorGroup("Hide Automatically") {
            ForEach(SensitiveKind.allCases) { kind in
                LabeledContent {
                    if running == kind {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Hide") { Task { await find(kind) } }
                            .buttonStyle(.glass)
                            .disabled(running != nil)
                    }
                } label: {
                    Label(kind.title, systemImage: kind.symbolName)
                }
            }
        } footer: {
            Text(result ?? String(localized: "Found on this Mac with Vision. Each area gets its own mark you can adjust or delete."))
                .contentTransition(.opacity)
        }
        .animation(.response, value: running)
        .animation(.response, value: result)
    }

    private func find(_ kind: SensitiveKind) async {
        running = kind
        defer { running = nil }
        do {
            let areas = try await TextRecognizer.sensitiveAreas(in: document.image, kinds: [kind])
            document.addRedactions(areas)
            switch areas.count {
            case 0: result = String(localized: "Nothing to hide was found.")
            case 1: result = String(localized: "Covered 1 area.")
            default: result = String(localized: "Covered \(areas.count) areas.")
            }
        } catch {
            result = error.localizedDescription
        }
    }
}

#Preview("Inspector fits content") {
    EditorInspectorPreview.make(tool: .select, maxHeight: 620)
        .frame(width: 340, height: 700)
}

#Preview("Inspector scrolls when needed") {
    EditorInspectorPreview.make(tool: .arrow, maxHeight: 240)
        .frame(width: 340, height: 320)
}

#Preview("Arrow inspector fits content") {
    EditorInspectorPreview.make(tool: .arrow, maxHeight: 620)
        .frame(width: 340, height: 700)
}

#Preview("Spotlight inspector fits content") {
    EditorInspectorPreview.make(tool: .spotlight, maxHeight: 620)
        .frame(width: 340, height: 700)
}

@MainActor
private enum EditorInspectorPreview {
    static func make(tool: EditorTool, maxHeight: CGFloat) -> some View {
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let document = EditorDocument(image: context.makeImage()!, scale: 1, fileURL: nil)
        document.tool = tool

        return ZStack(alignment: .top) {
            Color(nsColor: .underPageBackgroundColor)
            EditorInspector(
                document: document,
                chrome: .panel(
                    grip: InspectorGrip(placement: .constant(.right), onDrag: { _ in }, onDrop: { _ in }),
                    maxHeight: maxHeight
                ),
                onLiftSubject: {},
                isLiftingSubject: false
            )
            .padding(.top, 12)
        }
    }
}
