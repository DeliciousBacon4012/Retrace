import AppKit
import SwiftUI

/// Every setting for the selected mark, or for the next mark the current tool draws, in a
/// grouped form of standard controls on a floating panel of system Liquid Glass.
/// Changes apply live and become the tool's style for next time.
struct EditorInspector: View {
    @Bindable var document: EditorDocument

    static let width: CGFloat = 280
    private static let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    var body: some View {
        let tool = document.inspectedTool

        Form {
            Section {
                InspectorHeader(tool: tool, isSelection: document.selected != nil)
            }

            switch tool {
            case .select:
                Section {
                    Text("Click a mark to change it. Drag its handles to reshape it, or drag the mark to move it.")
                        .foregroundStyle(.secondary)
                }
            case .crop:
                CropSection(document: document)
            default:
                VariantSection(document: document, tool: tool)
                ColorSection(document: document, tool: tool)
                ToolSection(document: document, tool: tool)
                if tool != .highlighter, tool != .redact {
                    EffectsSection(document: document)
                }
                if tool == .redact, document.selected == nil {
                    AutoRedactSection(document: document)
                }
            }

            if document.selected != nil {
                ArrangeSection(document: document)
            }

            if tool.draws {
                Section {
                    Button("Reset to Default Style") {
                        withAnimation(.response) { document.resetStyle() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        .controlSize(.small)
        .animation(.smooth(duration: 0.22), value: tool)
        .frame(width: Self.width)
        .clipShape(Self.shape)
        .glassEffect(.regular, in: Self.shape)
    }
}

private struct InspectorHeader: View {
    let tool: EditorTool
    let isSelection: Bool

    var body: some View {
        LabeledContent {
            Text(String(tool.key).uppercased())
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .help("Press \(String(tool.key).uppercased()) to pick this tool")
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(tool.title)
                        .font(.headline)
                    Text(isSelection ? "Selected mark" : (tool.draws ? "Next mark" : "Tool"))
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
            Section("Arrow") {
                Picker("Type", selection: $document.style.route) {
                    ForEach(ArrowRoute.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
                Picker("Start", selection: $document.style.startHead) {
                    ForEach(ArrowHead.allCases) { Text($0.title).tag($0) }
                }
                Picker("End", selection: $document.style.endHead) {
                    ForEach(ArrowHead.allCases) { Text($0.title).tag($0) }
                }
                Button("Swap Ends") {
                    let start = document.style.startHead
                    document.style.startHead = document.style.endHead
                    document.style.endHead = start
                }
            }
        case .shape:
            Section("Shape") {
                Picker("Shape", selection: $document.style.shape) {
                    ForEach(ShapeKind.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
                Picker("Fill", selection: $document.style.fill) {
                    ForEach(ShapeFill.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        case .redact:
            Section("Redaction") {
                Picker("Type", selection: $document.style.redaction) {
                    ForEach(Redaction.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Shape", selection: $document.style.shape) {
                    ForEach(ShapeKind.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
            }
        case .text:
            Section("Text") {
                Picker("Style", selection: $document.style.textStyle) {
                    ForEach(TextStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Font", selection: $document.style.font) {
                    ForEach(TextFont.allCases) { Text($0.title).tag($0) }
                }
                Picker("Weight", selection: $document.style.weight) {
                    ForEach(TextWeight.allCases) { Text($0.title).tag($0) }
                }
            }
        case .counter:
            Section("Counter") {
                Picker("Style", selection: $document.style.counterStyle) {
                    ForEach(CounterStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
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

    var body: some View {
        if tool != .redact || document.style.redaction == .solid {
            Section("Color") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 8) {
                    ForEach(Array(zip(palette.colors, palette.names).enumerated()), id: \.offset) { index, swatch in
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
                if tool != .redact {
                    ValueSlider("Opacity", value: $document.style.opacity, in: 0.1...1, format: .percent)
                }
            }
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
            Section("Line") {
                ValueSlider("Thickness", value: points(\.lineWidth), in: 1...30, unit: "pt")
                ValueSlider("Head Size", value: $document.style.headScale, in: 0.5...2.5, format: .percent)
                Toggle("Tapered", isOn: $document.style.tapered)
                Toggle("Dashed", isOn: $document.style.dashed)
            }
        case .shape:
            Section("Border") {
                ValueSlider("Thickness", value: points(\.lineWidth), in: 0...30, unit: "pt")
                if document.style.shape == .rectangle {
                    ValueSlider("Roundness", value: points(\.cornerRadius), in: 0...80, unit: "pt")
                }
                Toggle("Dashed", isOn: $document.style.dashed)
            }
        case .pen:
            Section("Stroke") {
                ValueSlider("Thickness", value: points(\.lineWidth), in: 1...30, unit: "pt")
                Toggle("Dashed", isOn: $document.style.dashed)
            }
        case .highlighter:
            Section {
                ValueSlider("Thickness", value: points(\.lineWidth), in: 4...60, unit: "pt")
                Toggle("Snap to text", isOn: $snapsToText)
            } header: {
                Text("Stroke")
            } footer: {
                if snapsToText {
                    Text("Drag along a line of text to cover its words neatly. Hold Shift for a straight stroke anywhere.")
                } else {
                    Text("Hold Shift while dragging for a perfectly straight stroke.")
                }
            }
            .onChange(of: snapsToText) {
                if snapsToText { document.prepareTextLines() }
            }
        case .text:
            Section("Size") {
                ValueSlider("Size", value: points(\.fontSize), in: 8...120, unit: "pt")
            }
        case .counter:
            Section("Size") {
                ValueSlider("Size", value: points(\.fontSize), in: 10...64, unit: "pt")
            }
        case .redact:
            if document.style.redaction != .solid || document.style.shape == .rectangle {
                Section {
                    if document.style.redaction != .solid {
                        ValueSlider("Strength", value: $document.style.strength, in: 0...1, format: .percent)
                    }
                    if document.style.shape == .rectangle {
                        ValueSlider("Roundness", value: points(\.cornerRadius), in: 0...80, unit: "pt")
                    }
                } header: {
                    Text("Amount")
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
        Section("Shadow") {
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

    private let ratios: [(String, CGFloat)] = [("16:9", 16 / 9), ("4:3", 4 / 3), ("1:1", 1), ("3:4", 3 / 4), ("9:16", 9 / 16)]

    var body: some View {
        Section {
            LabeledContent("Aspect Ratio") {
                Menu("Choose") {
                    ForEach(ratios, id: \.0) { title, ratio in
                        Button(title) { document.applyCropAspect(ratio) }
                    }
                }
                .fixedSize()
            }
            HStack {
                Button("Reset") { document.resetCrop() }
                    .disabled(document.cropRect == nil)
                Spacer()
                Button("Crop") { document.commitCrop() }
                    .buttonStyle(.borderedProminent)
            }
        } header: {
            Text("Crop")
        } footer: {
            Text("Drag the handles or the box. Press Return to crop, or Esc to cancel. Hold Shift for a square.")
        }
    }
}

/// Order, duplicate, and delete for the selected mark.
private struct ArrangeSection: View {
    let document: EditorDocument

    var body: some View {
        Section("Arrange") {
            HStack {
                ControlGroup {
                    Button("Duplicate", systemImage: "plus.square.on.square") { document.duplicateSelection() }
                        .help("Duplicate (⌘D)")
                    Button("Bring to Front", systemImage: "square.3.layers.3d.top.filled") { document.bringSelectionToFront() }
                        .help("Bring to Front (⌘])")
                    Button("Send to Back", systemImage: "square.3.layers.3d.bottom.filled") { document.sendSelectionToBack() }
                        .help("Send to Back (⌘[)")
                }
                .fixedSize()
                Spacer()
                Button("Delete", systemImage: "trash", role: .destructive) { document.deleteSelection() }
                    .help("Delete (⌫)")
            }
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
        Section {
            ForEach(SensitiveKind.allCases) { kind in
                LabeledContent {
                    if running == kind {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Hide") { Task { await find(kind) } }
                            .disabled(running != nil)
                    }
                } label: {
                    Label(kind.title, systemImage: kind.symbolName)
                }
            }
        } header: {
            Text("Hide Automatically")
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
