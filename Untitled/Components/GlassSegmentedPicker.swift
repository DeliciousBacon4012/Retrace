import SwiftUI

/// A row of choices on Liquid Glass. The chosen one is tinted and slides to the next
/// choice; press and drag across the row to slide through them, like a segmented control.
struct GlassSegmentedPicker<Value: Hashable, Item: View>: View {
    private let title: LocalizedStringKey
    @Binding private var selection: Value
    private let options: [Value]
    private let name: (Value) -> String
    private let item: (Value) -> Item

    @Namespace private var highlight
    @State private var width: CGFloat = 0

    /// - Parameters:
    ///   - name: The choice's name, for its tooltip and VoiceOver.
    ///   - item: How the choice looks: a short word or a symbol.
    init(
        _ title: LocalizedStringKey,
        selection: Binding<Value>,
        options: [Value],
        name: @escaping (Value) -> String,
        @ViewBuilder item: @escaping (Value) -> Item
    ) {
        self.title = title
        _selection = selection
        self.options = options
        self.name = name
        self.item = item
    }

    var body: some View {
        LabeledContent(title) {
            GlassEffectContainer {
                HStack(spacing: 0) {
                    ForEach(options, id: \.self) { option in
                        segment(option)
                    }
                }
                .padding(2)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .contentShape(.capsule)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard let option = option(at: value.location.x), option != selection else { return }
                        selection = option
                    }
            )
            .animation(.smooth(duration: 0.25), value: selection)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
        }
    }

    private func segment(_ option: Value) -> some View {
        let isSelected = option == selection
        return item(option)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 20)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.accentColor)
                        .matchedGeometryEffect(id: "selection", in: highlight)
                }
            }
            .help(name(option))
            // Each choice is its own button for VoiceOver, at exactly where it's drawn.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name(option))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { selection = option }
    }

    /// The choice under a point on the row, counting the 2-point inset.
    private func option(at x: CGFloat) -> Value? {
        let inner = width - 4
        guard inner > 0, !options.isEmpty else { return nil }
        let index = Int(((x - 2) / inner * CGFloat(options.count)).rounded(.down))
        return options[min(max(index, 0), options.count - 1)]
    }
}
