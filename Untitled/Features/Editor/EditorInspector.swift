import AppKit
import SwiftUI

/// Every setting for the selected mark, or for the next mark the current tool draws, on a
/// floating Liquid Glass panel. Changes apply live and become the tool's style for next time.
///
/// Rows have fixed heights and values use fixed-width digits, so dragging a slider never
/// moves anything else on the panel.
struct EditorInspector: View {
    @Bindable var document: EditorDocument

    static let width: CGFloat = 268

    var body: some View {
        let tool = document.inspectedTool

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                InspectorHeader(tool: tool, isSelection: document.selected != nil)

                switch tool {
                case .select:
                    Text("Click a mark to change it. Drag its handles to reshape it, or drag the mark to move it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
                    Button("Reset to Default Style", systemImage: "arrow.counterclockwise") {
                        withAnimation(.response) { document.resetStyle() }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(16)
            .id(tool)
            .transition(.opacity)
        }
        .scrollIndicators(.never)
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        .frame(width: Self.width)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .animation(.smooth(duration: 0.22), value: tool)
        .controlSize(.small)
    }
}

private struct InspectorHeader: View {
    let tool: EditorTool
    let isSelection: Bool

    var body: some View {
        HStack(spacing: Design.spacingM) {
            Image(systemName: tool.symbolName)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .glassEffect(.regular.tint(.accentColor.opacity(0.25)), in: .rect(cornerRadius: Design.radiusS))
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 1) {
                Text(tool.title)
                    .font(.headline)
                    .contentTransition(.opacity)
                Text(isSelection ? "Selected mark" : (tool.draws ? "Next mark" : "Tool"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
            }
            Spacer()
            Text(String(tool.key).uppercased())
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 5))
                .help("Press \(String(tool.key).uppercased()) to pick this tool")
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
            InspectorGroup("Arrow") {
                GlassSegmentedPicker(title: "Type", selection: $document.style.route, options: ArrowRoute.allCases, label: \.title, symbol: { $0.symbolName })
                InspectorRow("Start") {
                    GlassMenuPicker(title: "Start", selection: $document.style.startHead, options: ArrowHead.allCases, label: \.title)
                }
                InspectorRow("End") {
                    GlassMenuPicker(title: "End", selection: $document.style.endHead, options: ArrowHead.allCases, label: \.title)
                }
                Button("Swap Ends", systemImage: "arrow.left.arrow.right") {
                    let start = document.style.startHead
                    document.style.startHead = document.style.endHead
                    document.style.endHead = start
                }
                .buttonStyle(.glass)
                .frame(maxWidth: .infinity)
                .help("Swap the start and end")
            }
        case .shape:
            InspectorGroup("Shape") {
                GlassSegmentedPicker(title: "Shape", selection: $document.style.shape, options: ShapeKind.allCases, label: \.title, symbol: { $0.symbolName })
                GlassSegmentedPicker(title: "Fill", selection: $document.style.fill, options: ShapeFill.allCases, label: \.title)
            }
        case .redact:
            InspectorGroup("Type") {
                GlassSegmentedPicker(title: "Type", selection: $document.style.redaction, options: Redaction.allCases, label: \.title)
                GlassSegmentedPicker(title: "Shape", selection: $document.style.shape, options: ShapeKind.allCases, label: \.title, symbol: { $0.symbolName })
            }
        case .text:
            InspectorGroup("Text") {
                GlassSegmentedPicker(title: "Style", selection: $document.style.textStyle, options: TextStyle.allCases, label: \.title)
                InspectorRow("Font") {
                    GlassMenuPicker(title: "Font", selection: $document.style.font, options: TextFont.allCases, label: \.title)
                }
                InspectorRow("Weight") {
                    GlassMenuPicker(title: "Weight", selection: $document.style.weight, options: TextWeight.allCases, label: \.title)
                }
            }
        case .counter:
            InspectorGroup("Style") {
                GlassSegmentedPicker(title: "Style", selection: $document.style.counterStyle, options: CounterStyle.allCases, label: \.title)
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

    var body: some View {
        if tool != .redact || document.style.redaction == .solid {
            InspectorGroup("Color") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 8) {
                    ForEach(Array(RGBAColor.presets.enumerated()), id: \.offset) { index, preset in
                        Swatch(color: preset, isSelected: preset == document.style.color) {
                            withAnimation(.response) { document.style.color = preset }
                        }
                        .help("Color \(index + 1) (\(index == 9 ? 0 : index + 1))")
                    }
                }
                .padding(.vertical, 2)
                InspectorRow("Custom") {
                    ColorPicker("Custom", selection: customColor, supportsOpacity: false)
                        .labelsHidden()
                }
                if tool != .redact {
                    ValueSlider("Opacity", value: $document.style.opacity, in: 0.1...1, format: .percent)
                }
            }
        }
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
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.swiftUIColor)
                .overlay { Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 1) }
                .padding(isSelected ? 3 : 0)
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                            .transition(.scale(1.3).combined(with: .opacity))
                    }
                }
                .frame(width: 26, height: 26)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Color")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The settings that only make sense for one tool.
private struct ToolSection: View {
    @Bindable var document: EditorDocument
    let tool: EditorTool

    var body: some View {
        switch tool {
        case .arrow:
            InspectorGroup("Line") {
                ValueSlider("Thickness", value: points(\.lineWidth), in: 1...30, unit: "pt")
                ValueSlider("Head Size", value: $document.style.headScale, in: 0.5...2.5, format: .percent)
                InspectorToggle("Tapered", isOn: $document.style.tapered)
                InspectorToggle("Dashed", isOn: $document.style.dashed)
            }
        case .shape:
            InspectorGroup("Border") {
                ValueSlider("Thickness", value: points(\.lineWidth), in: 0...30, unit: "pt")
                if document.style.shape == .rectangle {
                    ValueSlider("Roundness", value: points(\.cornerRadius), in: 0...80, unit: "pt")
                }
                InspectorToggle("Dashed", isOn: $document.style.dashed)
            }
        case .pen:
            InspectorGroup("Stroke") {
                ValueSlider("Thickness", value: points(\.lineWidth), in: 1...30, unit: "pt")
                InspectorToggle("Dashed", isOn: $document.style.dashed)
            }
        case .highlighter:
            InspectorGroup("Stroke") {
                ValueSlider("Thickness", value: points(\.lineWidth), in: 4...60, unit: "pt")
                Label("Hold Shift while dragging for a perfectly straight stroke.", systemImage: "shift")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .text:
            InspectorGroup("Size") {
                ValueSlider("Size", value: points(\.fontSize), in: 8...120, unit: "pt")
            }
        case .counter:
            InspectorGroup("Size") {
                ValueSlider("Size", value: points(\.fontSize), in: 10...64, unit: "pt")
            }
        case .redact:
            InspectorGroup("Redaction") {
                if document.style.redaction != .solid {
                    ValueSlider("Strength", value: $document.style.strength, in: 0...1, format: .percent)
                }
                if document.style.shape == .rectangle {
                    ValueSlider("Roundness", value: points(\.cornerRadius), in: 0...80, unit: "pt")
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
            InspectorToggle("Shadow", isOn: $document.style.shadow.animation(.response))
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
        InspectorGroup("Crop") {
            Text("Drag the handles or the box. Press Return to crop, or Esc to cancel. Hold Shift for a square.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            GlassEffectContainer(spacing: 6) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(ratios, id: \.0) { title, ratio in
                        Button(title) { document.applyCropAspect(ratio) }
                            .buttonStyle(.glass)
                            .font(.system(.callout, design: .monospaced))
                    }
                }
            }
            HStack {
                Button("Reset", systemImage: "arrow.counterclockwise") { document.resetCrop() }
                    .buttonStyle(.glass)
                    .disabled(document.cropRect == nil)
                Spacer()
                Button("Crop") { document.commitCrop() }
                    .buttonStyle(.glassProminent)
            }
        }
    }
}

/// Order, duplicate, and delete for the selected mark.
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
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
            }
        }
    }
}

/// An on/off switch row.
private struct InspectorToggle: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool

    init(_ title: LocalizedStringKey, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .toggleStyle(.switch)
        .frame(minHeight: 26)
    }
}

/// A slider with its title above and its value in fixed-width digits, so the value
/// changing never resizes the row or nudges the slider under the pointer.
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
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatted)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.primary)
                    .frame(width: 52, alignment: .trailing)
            }
            Slider(value: $value, in: range)
                .labelsHidden()
        }
        .frame(height: 46)
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
                Button {
                    Task { await find(kind) }
                } label: {
                    HStack {
                        Label(kind.title, systemImage: kind.symbolName)
                        Spacer(minLength: 0)
                        if running == kind {
                            ProgressView().controlSize(.small)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.glass)
                .disabled(running != nil)
            }
            Text(result ?? String(localized: "Found on this Mac with Vision. Each area gets its own mark you can adjust or delete."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
