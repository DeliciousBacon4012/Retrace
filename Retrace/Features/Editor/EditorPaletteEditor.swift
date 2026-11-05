import AppKit
import SwiftUI

/// Native color controls for the twelve reusable editor palette slots.
struct EditorPaletteEditor: View {
    @Binding private var encodedColors: Data
    @Environment(\.dismiss) private var dismiss
    @State private var colors: [RGBAColor]

    init(encodedColors: Binding<Data>) {
        _encodedColors = encodedColors
        _colors = State(initialValue: EditorPalette.customColors(from: encodedColors.wrappedValue))
    }

    var body: some View {
        Form {
            Section("Custom palette") {
                ForEach(0..<EditorPalette.customColorCount, id: \.self) { index in
                    ColorPicker("Color \(index + 1)", selection: colorBinding(at: index), supportsOpacity: false)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 360, idealWidth: 400, minHeight: 420, idealHeight: 520)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    if let data = try? JSONEncoder().encode(colors) {
                        encodedColors = data
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func colorBinding(at index: Int) -> Binding<Color> {
        Binding {
            colors[index].swiftUIColor
        } set: { newValue in
            guard let resolved = NSColor(newValue).usingColorSpace(.sRGB) else { return }
            colors[index] = RGBAColor(
                red: Double(resolved.redComponent),
                green: Double(resolved.greenComponent),
                blue: Double(resolved.blueComponent)
            )
        }
    }
}
