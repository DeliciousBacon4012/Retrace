import SwiftUI

/// A segmented control made of Liquid Glass: the selected segment is a tinted glass pill
/// that slides and morphs to the one you pick.
struct GlassSegmentedPicker<Value: Hashable & Identifiable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String
    let symbol: ((Value) -> String)?

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(title: LocalizedStringKey, selection: Binding<Value>, options: [Value], label: @escaping (Value) -> String, symbol: ((Value) -> String)? = nil) {
        self.title = title
        _selection = selection
        self.options = options
        self.label = label
        self.symbol = symbol
    }

    var body: some View {
        GlassEffectContainer(spacing: 2) {
            HStack(spacing: 2) {
                ForEach(options) { option in
                    segment(option)
                }
            }
            .padding(3)
            .glassEffect(.regular, in: .capsule)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }

    private func segment(_ option: Value) -> some View {
        let isSelected = option == selection
        return Button {
            withAnimation(reduceMotion ? nil : .pop) { selection = option }
        } label: {
            Group {
                if let symbol {
                    Image(systemName: symbol(option))
                        .imageScale(.medium)
                } else {
                    Text(label(option))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .font(.callout.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, minHeight: 26)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                Capsule()
                    .fill(Color.accentColor)
                    .matchedGeometryEffect(id: "selection", in: namespace)
                    .shadow(color: .accentColor.opacity(0.35), radius: 6, y: 2)
            }
        }
        .help(label(option))
        .accessibilityLabel(label(option))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A pop-up menu shown as a glass capsule, for choices with too many words for segments.
struct GlassMenuPicker<Value: Hashable & Identifiable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options) { Text(label($0)).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 6) {
                Text(label(selection))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.glass)
        .accessibilityLabel(Text(title))
        .accessibilityValue(label(selection))
    }
}

/// A titled row in a floating inspector: label on the left, control on the right,
/// with a fixed height so changing a value never shifts anything around it.
struct InspectorRow<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(spacing: Design.spacingS) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minHeight: 30)
    }
}

/// A group of inspector rows with a small heading, without a box around it.
struct InspectorGroup<Content: View>: View {
    let title: LocalizedStringKey?
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
