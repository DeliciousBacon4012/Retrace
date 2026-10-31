import AppKit
import SwiftUI

/// Every setting for the selected mark, or for the next mark the current tool draws.
/// Changes apply live and become the tool's style for next time.
struct EditorInspector: View {
    @Bindable var document: EditorDocument

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
                        .font(.callout)
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
                    Button("Reset to Default Style", systemImage: "arrow.counterclockwise") {
                        withAnimation(.response) { document.resetStyle() }
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .animation(.response, value: tool)
        .animation(.response, value: document.selectedID)
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

/// The dropdown that picks a tool's variant, like Blur, Mosaic or Redact.
private struct VariantSection: View {
    @Bindable var document: EditorDocument
    let tool: EditorTool

    var body: some View {
        switch tool {
        case .arrow:
            Section {
                Picker("Type", selection: $document.style.route) {
                    ForEach(ArrowRoute.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                }
                .pickerStyle(.menu)
                HStack {
                    Picker("Start", selection: $document.style.startHead) {
                        ForEach(ArrowHead.allCases) { Text($0.title).tag($0) }
                    }
                    Button("Swap Ends", systemImage: "arrow.left.arrow.right") {
                        let start = document.style.startHead
                        document.style.startHead = document.style.endHead
                        document.style.endHead = start
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Swap the start and end")
                }
                Picker("End", selection: $document.style.endHead) {
                    ForEach(ArrowHead.allCases) { Text($0.title).tag($0) }
                }
            }
        case .shape:
            Section {
                Picker("Shape", selection: $document.style.shape) {
                    ForEach(ShapeKind.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Fill", selection: $document.style.fill) {
                    ForEach(ShapeFill.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        case .redact:
            Section {
                Picker("Type", selection: $document.style.redaction) {
                    ForEach(Redaction.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                }
                .pickerStyle(.menu)
                Picker("Shape", selection: $document.style.shape) {
                    ForEach(ShapeKind.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        case .text:
            Section {
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
            Section {
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

    var body: some View {
        if tool != .redact || document.style.redaction == .solid {
            Section("Color") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 8) {
                    ForEach(Array(RGBAColor.presets.enumerated()), id: \.offset) { index, preset in
                        Swatch(color: preset, isSelected: preset == document.style.color) {
                            withAnimation(.response) { document.style.color = preset }
                        }
                        .help("Color \(index + 1) (\(index == 9 ? 0 : index + 1))")
                    }
                }
                .padding(.vertical, 2)
                ColorPicker("Custom", selection: customColor, supportsOpacity: false)
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
            } footer: {
                Label("Hold Shift while dragging for a perfectly straight stroke.", systemImage: "shift")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            Section("Redaction") {
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
        let scale = document.scale
        return Binding {
            Double(document.style[keyPath: keyPath] / scale)
        } set: { newValue in
            document.style[keyPath: keyPath] = CGFloat(newValue) * scale
        }
    }
}

/// Drop shadow.
private struct EffectsSection: View {
    @Bindable var document: EditorDocument

    var body: some View {
        Section("Shadow") {
            Toggle("Shadow", isOn: $document.style.shadow.animation(.response))
            if document.style.shadow {
                ValueSlider("Softness", value: points(\.shadowRadius), in: 0...30, unit: "pt")
                ValueSlider("Darkness", value: $document.style.shadowOpacity, in: 0.05...0.8, format: .percent)
            }
        }
    }

    private func points(_ keyPath: WritableKeyPath<MarkStyle, CGFloat>) -> Binding<Double> {
        let scale = document.scale
        return Binding {
            Double(document.style[keyPath: keyPath] / scale)
        } set: { newValue in
            document.style[keyPath: keyPath] = CGFloat(newValue) * scale
        }
    }
}

/// Aspect presets for the crop tool.
private struct CropSection: View {
    let document: EditorDocument

    private let ratios: [(String, CGFloat)] = [("16:9", 16 / 9), ("4:3", 4 / 3), ("1:1", 1), ("3:4", 3 / 4), ("9:16", 9 / 16)]

    var body: some View {
        Section {
            Text("Drag over the image to crop it. Hold Shift for a square.")
                .font(.callout)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(ratios, id: \.0) { title, ratio in
                    Button(title) { document.applyCropAspect(ratio) }
                        .buttonStyle(.glass)
                        .font(.system(.callout, design: .monospaced))
                }
            }
            Button("Reset Crop", systemImage: "arrow.counterclockwise") { document.resetCrop() }
                .disabled(document.cropRect == nil)
        }
    }
}

/// Order, duplicate, and delete for the selected mark.
private struct ArrangeSection: View {
    let document: EditorDocument

    var body: some View {
        Section("Arrange") {
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

/// A labelled slider with its value shown in monospaced digits.
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
            HStack(spacing: Design.spacingS) {
                Slider(value: $value, in: range)
                    .labelsHidden()
                Text(formatted)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
                    .contentTransition(.numericText(value: value))
            }
        }
    }

    private var formatted: String {
        switch format {
        case .percent: value.formatted(.percent.precision(.fractionLength(0)))
        case .number(let unit): "\(Int(value.rounded()))\(unit)"
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
                Button {
                    Task { await find(kind) }
                } label: {
                    HStack {
                        Label(kind.title, systemImage: kind.symbolName)
                        Spacer()
                        if running == kind {
                            ProgressView().controlSize(.small)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .disabled(running != nil)
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
