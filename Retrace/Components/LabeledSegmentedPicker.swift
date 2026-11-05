import SwiftUI

/// A native segmented picker. SwiftUI provides its appearance, hit testing, keyboard
/// navigation, and accessibility behavior.
struct LabeledSegmentedPicker<Value: Hashable, Item: View>: View {
    private let title: LocalizedStringKey
    @Binding private var selection: Value
    private let options: [Value]
    private let name: (Value) -> String
    private let item: (Value) -> Item

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
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    item(option)
                        .tag(option)
                        .help(name(option))
                }
            }
            .capsuleSegmentedStyle()
            .labelsHidden()
            .accessibilityLabel(title)
        }
    }
}
