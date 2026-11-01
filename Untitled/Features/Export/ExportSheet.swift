import AppKit
import OSLog
import SwiftUI

/// An image waiting to be exported, with what's needed to name and size it.
struct ExportItem: Identifiable {
    let id = UUID()
    let image: CGImage
    /// Pixels per point of the original capture.
    let scale: CGFloat
    let suggestedName: String
    /// Hidden areas were drawn over. The file then never carries metadata.
    var hidesContent = false
}

/// Export with a live preview of the result: format, quality, size, color, and metadata,
/// plus the file size before anything is written.
struct ExportSheet: View {
    let item: ExportItem
    let folder: URL
    let onExported: (URL) -> Void

    @State private var options: ExportOptions
    @State private var estimatedBytes: Int?
    @State private var isEstimating = false
    @State private var limitsSize = false
    @State private var limitKilobytes = 1000.0
    @Environment(\.dismiss) private var dismiss

    init(item: ExportItem, folder: URL, options: ExportOptions, onExported: @escaping (URL) -> Void) {
        self.item = item
        self.folder = folder
        self.onExported = onExported
        _options = State(initialValue: options)
    }

    private var effectiveOptions: ExportOptions {
        var result = options
        result.maximumBytes = limitsSize && options.format.isLossy ? Int(limitKilobytes * 1000) : nil
        if item.hidesContent { result.stripsMetadata = true }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: Design.spacingXL) {
                preview
                Form {
                    Section {
                        Picker("Format", selection: $options.format) {
                            ForEach(ImageFormat.writable) { Text($0.title).tag($0) }
                        }
                        if options.format.isLossy {
                            ValueSlider("Quality", value: $options.quality, in: 0.05...1, format: .percent)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            Toggle("Limit file size", isOn: $limitsSize.animation(.response))
                            if limitsSize {
                                LabeledContent("Largest size") {
                                    HStack {
                                        TextField("Kilobytes", value: $limitKilobytes, format: .number.precision(.fractionLength(0)))
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 80)
                                        Text("KB").foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    Section("Size") {
                        ValueSlider("Scale", value: $options.scalePercent, in: 10...100, unit: "%")
                        if item.scale > 1 {
                            Button("Standard Resolution (1×)") {
                                withAnimation(.response) { options.scalePercent = 100 / item.scale }
                            }
                            .buttonStyle(.link)
                        }
                    }
                    Section("Privacy and Color") {
                        Toggle("Remove metadata", isOn: item.hidesContent ? .constant(true) : $options.stripsMetadata)
                            .disabled(item.hidesContent)
                            .help(item.hidesContent ? "Always on for images with redactions" : "")
                        Toggle("Convert to sRGB", isOn: $options.convertsToSRGB)
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .frame(width: 340)
                .animation(.response, value: options.format)
            }
            .padding(Design.spacingXL)

            Divider()

            HStack(spacing: Design.spacingM) {
                summary
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Export…") { export() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Design.spacingL)
        }
        .frame(minWidth: 720)
        .task(id: effectiveOptions) {
            await estimate()
        }
    }

    private var preview: some View {
        Image(decorative: item.image, scale: 1)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 300, maxHeight: 280)
            .clipShape(.rect(cornerRadius: Design.radiusS))
            .overlay {
                RoundedRectangle(cornerRadius: Design.radiusS)
                    .strokeBorder(.separator, lineWidth: 0.5)
            }
            .frame(width: 316, height: 296)
    }

    private var summary: some View {
        let size = ImageEncoder.outputSize(of: item.image, options: options)
        return VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(Int(size.width)) × \(Int(size.height)) px · \(options.format.title)")
                .font(.system(.callout, design: .monospaced).weight(.medium))
                .contentTransition(.numericText())
            HStack(spacing: 6) {
                if let estimatedBytes {
                    Text(estimatedBytes.formatted(.byteCount(style: .file)))
                        .contentTransition(.numericText())
                }
                if isEstimating {
                    ProgressView().controlSize(.mini)
                }
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .animation(.response, value: estimatedBytes)
    }

    private func estimate() async {
        // Let a slider settle before encoding.
        try? await Task.sleep(for: .milliseconds(160))
        guard !Task.isCancelled else { return }
        isEstimating = true
        defer { isEstimating = false }
        do {
            let data = try await ImageEncoder.encodeInBackground(item.image, options: effectiveOptions, pointScale: item.scale)
            guard !Task.isCancelled else { return }
            estimatedBytes = data.count
        } catch {
            estimatedBytes = nil
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [options.format.utType]
        panel.directoryURL = folder
        panel.nameFieldStringValue = item.suggestedName + "." + options.format.fileExtension
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try ImageEncoder.data(for: item.image, options: effectiveOptions, pointScale: item.scale)
            try data.write(to: url, options: .atomic)
            Log.capture.info("Exported an image")
            onExported(url)
            dismiss()
        } catch {
            Log.capture.error("Export failed: \(error.localizedDescription, privacy: .public)")
            ErrorPresenter.present(error)
        }
    }
}
