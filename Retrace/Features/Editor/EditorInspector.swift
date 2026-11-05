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
    let extractedText: String?
    let onCopyText: (String) -> Void
    let onCopyImage: () -> Void
    let imageTransfer: () -> EditorImageTransfer
    let onLiftSubject: () -> Void
    let isLiftingSubject: Bool

    nonisolated static let width: CGFloat = 304
    private static let shape = RoundedRectangle(cornerRadius: Design.radiusL, style: .continuous)
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

        return VStack(alignment: .leading, spacing: 20) {
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
                        if let extractedText {
                            Button("Copy or Drag Text", systemImage: "text.viewfinder") {
                                onCopyText(extractedText)
                            }
                            .draggable(extractedText)
                            .help("Copy the last OCR result again, or drag it to another app.")
                        }

                        Button("Copy or Drag Image", systemImage: "photo") {
                            onCopyImage()
                        }
                        .draggable(imageTransfer())
                        .help("Copy the edited image, or drag a redaction-safe PNG to another app.")

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
                        .buttonStyle(.bordered)
                        .disabled(isLiftingSubject)
                        .help("Copy the foreground as a transparent image using on-device Vision. Existing redactions are included.")

                        IdentifySection(image: document.image)

                        Text("Select a mark to edit it. Drag the mark or its handles to adjust it. Shift-click or ⌘A selects several.")
                            .foregroundStyle(.secondary)
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
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.horizontal, Design.spacingL)
        .padding(.vertical, Design.spacingM)
        .labeledContentStyle(InspectorRowStyle())
        .capsuleControls()
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
/// A label on the left and its control on the right, so every row lines up with the next.
private struct InspectorRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Design.spacingS) {
            configuration.label
                .frame(minWidth: 72, alignment: .leading)
            Spacer(minLength: 0)
            configuration.content
        }
    }
}

/// A pop-up button in an inspector row.
private struct InspectorPicker<Value: Hashable, Options: View>: View {
    let title: LocalizedStringKey
    @Binding var selection: Value
    @ViewBuilder let options: Options

    init(_ title: LocalizedStringKey, selection: Binding<Value>, @ViewBuilder options: () -> Options) {
        self.title = title
        _selection = selection
        self.options = options()
    }

    var body: some View {
        LabeledContent(title) {
            Picker(title, selection: $selection) { options }
                .labelsHidden()
                .fixedSize()
        }
    }
}

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
        VStack(alignment: .leading, spacing: Design.spacingM) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
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
                LabeledSegmentedPicker("Type", selection: $document.style.route, options: ArrowRoute.allCases, name: \.title) { Image(systemName: $0.symbolName) }
                InspectorPicker("Start", selection: $document.style.startHead) {
                    ForEach(ArrowHead.allCases) { Text($0.title).tag($0) }
                }
                InspectorPicker("End", selection: $document.style.endHead) {
                    ForEach(ArrowHead.allCases) { Text($0.title).tag($0) }
                }
                Button("Swap Ends", systemImage: "arrow.left.arrow.right") {
                    let start = document.style.startHead
                    document.style.startHead = document.style.endHead
                    document.style.endHead = start
                }
                .buttonStyle(.bordered)
            }
        case .shape:
            InspectorGroup {
                LabeledSegmentedPicker("Shape", selection: $document.style.shape, options: ShapeKind.allCases, name: \.title) { Image(systemName: $0.symbolName) }
                LabeledSegmentedPicker("Fill", selection: $document.style.fill, options: ShapeFill.allCases, name: \.title) { Text($0.title) }
            }
        case .redact:
            InspectorGroup {
                LabeledSegmentedPicker("Type", selection: $document.style.redaction, options: Redaction.allCases, name: \.title) { Text($0.title) }
                LabeledSegmentedPicker("Shape", selection: $document.style.shape, options: ShapeKind.allCases, name: \.title) { Image(systemName: $0.symbolName) }
            }
        case .spotlight:
            InspectorGroup {
                LabeledSegmentedPicker("Shape", selection: $document.style.shape, options: ShapeKind.allCases, name: \.title) { Image(systemName: $0.symbolName) }
            }
        case .text:
            InspectorGroup {
                LabeledSegmentedPicker("Style", selection: $document.style.textStyle, options: TextStyle.allCases, name: \.title) { Text($0.title) }
                InspectorPicker("Font", selection: $document.style.font) {
                    ForEach(TextFont.allCases) { Text($0.title).tag($0) }
                }
                InspectorPicker("Weight", selection: $document.style.weight) {
                    ForEach(TextWeight.allCases) { Text($0.title).tag($0) }
                }
            }
        case .counter:
            InspectorGroup {
                LabeledSegmentedPicker("Style", selection: $document.style.counterStyle, options: CounterStyle.allCases, name: \.title) { Text($0.title) }
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
                    LabeledContent("Custom") {
                        ColorPicker("Custom", selection: customColor, supportsOpacity: false)
                            .labelsHidden()
                    }
                    InspectorPicker("Palette", selection: $palette) {
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
    @AppStorage(SmartCropMode.storageKey) private var smartCropMode: SmartCropMode = .attention
    @State private var message: String?

    var body: some View {
        InspectorGroup("Crop") {
            InspectorPicker("Aspect Ratio", selection: Binding(get: { document.cropAspect }, set: { document.setCropAspect($0) })) {
                Text(CropAspect.free.title).tag(CropAspect.free)
                Text(CropAspect.original.title).tag(CropAspect.original)
                Divider()
                ForEach(CropAspect.allCases.filter { $0 != .free && $0 != .original }) { Text($0.title).tag($0) }
            }
            InspectorPicker("Smart Crop", selection: $smartCropMode) {
                ForEach(SmartCropMode.allCases) { Text($0.title).tag($0) }
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
                    Label("Suggest Crop", systemImage: "viewfinder")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isFindingSubject)
            .help("Suggest a crop around the main subject using on-device Vision.")

            Button("Reset to Full Image") { document.resetCrop() }
                .buttonStyle(.bordered)
                .disabled(!document.isCropped)
        } footer: {
            Text(message ?? String(localized: "Drag the handles or move the box. Smart Crop uses on-device Vision; review its suggestion before applying. Press Return or Crop below the image to apply, or Esc to cancel."))
        }
    }

    @MainActor
    private func suggestCrop() async {
        guard !isFindingSubject else { return }
        isFindingSubject = true
        defer { isFindingSubject = false }
        do {
            guard let suggestion = try await TextRecognizer.attentionCrop(in: document.image, mode: smartCropMode),
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

/// What Vision recognizes in the image, on request.
private struct IdentifySection: View {
    let image: CGImage

    @State private var labels: [ImageLabel]?
    @State private var isReading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Task { await identify() }
            } label: {
                if isReading {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text("Looking…")
                    }
                } else {
                    Label("Identify Image", systemImage: "sparkle.magnifyingglass")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isReading)
            .help("Recognize what's in the image, on this Mac.")

            if let labels {
                if labels.isEmpty {
                    Text("Nothing recognized with confidence.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(labels.map(\.title).joined(separator: ", "))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func identify() async {
        isReading = true
        defer { isReading = false }
        let found = try? await ImageIntelligence.labels(in: image)
        withAnimation(.response) { labels = found ?? [] }
    }
}

/// Order, duplicate, and delete for the selected marks.
private struct ArrangeSection: View {
    let document: EditorDocument

    var body: some View {
        InspectorGroup("Arrange") {
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
            .buttonStyle(.bordered)
            .labelStyle(.iconOnly)
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
                            .buttonStyle(.bordered)
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
                extractedText: nil,
                onCopyText: { _ in },
                onCopyImage: {},
                imageTransfer: { EditorImageTransfer(image: nil) },
                onLiftSubject: {},
                isLiftingSubject: false
            )
            .padding(.top, 12)
        }
    }
}
