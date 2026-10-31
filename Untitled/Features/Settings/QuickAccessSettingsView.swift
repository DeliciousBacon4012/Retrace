import SwiftUI

/// Where the floating thumbnails appear, how fast they move, and when they leave.
struct QuickAccessSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Show a thumbnail after each capture", isOn: $settings.showsQuickAccess)
            } footer: {
                Text("Double-click a thumbnail to edit it. Drag it into any app, or flick it toward the screen edge to put it away.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Position") {
                CornerPicker(selection: $settings.overlayCorner)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Design.spacingS)
            }

            Section("Motion") {
                LabeledContent("Speed") {
                    GlassSegmentedPicker(title: "Speed", selection: $settings.overlaySpeed, options: OverlaySpeed.allCases, label: \.title)
                        .frame(maxWidth: 260)
                }
                Picker("Close automatically", selection: $settings.overlayAutoCloseSeconds) {
                    Text("Never").tag(0)
                    Text("After 5 seconds").tag(5)
                    Text("After 10 seconds").tag(10)
                    Text("After 30 seconds").tag(30)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(!settings.showsQuickAccess)
    }
}

/// A miniature screen with a glass button in each corner.
private struct CornerPicker: View {
    @Binding var selection: OverlayCorner
    @Namespace private var namespace

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Design.radiusM)
                .fill(.quaternary.opacity(0.5))
                .frame(width: 240, height: 150)

            VStack {
                HStack {
                    corner(.topLeft)
                    Spacer()
                    corner(.topRight)
                }
                Spacer()
                HStack {
                    corner(.bottomLeft)
                    Spacer()
                    corner(.bottomRight)
                }
            }
            .padding(10)
            .frame(width: 240, height: 150)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Thumbnail position")
    }

    private func corner(_ corner: OverlayCorner) -> some View {
        let isSelected = selection == corner
        return Button {
            withAnimation(.pop) { selection = corner }
        } label: {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary.opacity(0.35)))
                .frame(width: 46, height: 30)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(4)
        }
        .buttonStyle(.plain)
        .glassEffect(isSelected ? .regular.interactive() : .clear.interactive(), in: .rect(cornerRadius: 9))
        .help(corner.title)
        .accessibilityLabel(corner.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#if DEBUG
#Preview {
    QuickAccessSettingsView()
        .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
        .frame(width: 520)
}
#endif
