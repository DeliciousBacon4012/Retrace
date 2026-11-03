import SwiftUI

/// The Settings window (⌘,): a glass bar of tabs you can click, or press and slide across,
/// above a grouped form. The window fits each tab's content, up to a limit, and reopens on
/// the tab last used. Other places choose a tab through `MainWindowRouter.showSettings`.
struct SettingsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @AppStorage(SettingsPane.storageKey) private var selection: SettingsPane = .general
    /// Which way the pages slide: forward when the new tab is to the right.
    @State private var forward = true
    /// Each tab's content height, measured, so the window can fit it.
    @State private var heights: [SettingsPane: CGFloat] = [:]

    private static let width: CGFloat = 660
    private static let heightRange: ClosedRange<CGFloat> = 280...640

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(selection: Binding(get: { selection }, set: select))
                .padding(.horizontal, 16)
                .padding(.top, 10)

            ZStack {
                measuredPage(selection)
                    .id(selection)
                    .transition(.push(from: forward ? .trailing : .leading))
            }
            .frame(height: height)
            .clipped()
        }
        .frame(width: Self.width)
        .navigationTitle(selection.title)
        .animation(.smooth(duration: 0.3), value: height)
    }

    /// The measured height of the open tab, or a middle size until it has been measured.
    private var height: CGFloat {
        let measured = heights[selection] ?? 540
        return min(max(measured, Self.heightRange.lowerBound), Self.heightRange.upperBound)
    }

    private func select(_ pane: SettingsPane) {
        guard pane != selection else { return }
        let all = SettingsPane.allCases
        forward = (all.firstIndex(of: pane) ?? 0) > (all.firstIndex(of: selection) ?? 0)
        withAnimation(.smooth(duration: 0.3)) { selection = pane }
    }

    /// A tab's form, reporting how tall its content is.
    private func measuredPage(_ pane: SettingsPane) -> some View {
        page(for: pane)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
            } action: { _, height in
                heights[pane] = height
            }
    }

    /// Related topics share a tab, one after the other in the same form.
    @ViewBuilder
    private func page(for pane: SettingsPane) -> some View {
        switch pane {
        case .general:
            Group {
                GeneralSettingsView(launchAtLogin: dependencies.launchAtLogin)
                FilesPrivacySettingsView()
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.displayVersion)
                }
            }
            .settingsPage()
        case .capture:
            Group {
                CaptureSettingsView()
                AfterCaptureSettingsView()
            }
            .settingsPage()
        case .quickAccess:
            QuickAccessSettingsView().settingsPage()
        case .clipboard:
            ClipboardSettingsView().settingsPage()
        case .notifications:
            NotificationsSettingsView().settingsPage()
        case .editor:
            EditorSettingsView().settingsPage()
        case .recording:
            Group {
                RecordingSettingsView()
                ReplayBufferSettingsView()
            }
            .settingsPage()
        case .shortcuts:
            ShortcutsSettingsView().settingsPage()
        case .advanced:
            AdvancedSettingsView().settingsPage()
        }
    }
}

/// The tabs in one glass bar. Click a tab, or press anywhere on the bar and slide: the
/// highlight follows the pointer from tab to tab. Left and right arrows move it too.
private struct SettingsTabBar: View {
    @Binding var selection: SettingsPane
    @Namespace private var highlight
    @FocusState private var isFocused: Bool
    @State private var barWidth: CGFloat = 0

    private let panes = SettingsPane.allCases

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 0) {
                ForEach(panes) { pane in
                    tab(pane)
                }
            }
            .padding(4)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
        }
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard let pane = pane(at: value.location.x) else { return }
                    selection = pane
                }
        )
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .defaultFocus($isFocused, true)
        .onMoveCommand { direction in
            guard let index = panes.firstIndex(of: selection) else { return }
            switch direction {
            case .left where index > 0: selection = panes[index - 1]
            case .right where index < panes.count - 1: selection = panes[index + 1]
            default: break
            }
        }
        .accessibilityRepresentation {
            Picker("Settings", selection: $selection) {
                ForEach(panes) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private func tab(_ pane: SettingsPane) -> some View {
        let isSelected = pane == selection
        return VStack(spacing: 3) {
            Image(systemName: pane.symbolName)
                .font(.system(size: 16, weight: .medium))
                .symbolVariant(isSelected ? .fill : .none)
                .frame(height: 20)
            Text(pane.title)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.tint.opacity(0.16))
                    .matchedGeometryEffect(id: "selection", in: highlight)
            }
        }
        .help(pane.title)
    }

    /// The tab under a point on the bar, counting the 4-point inset.
    private func pane(at x: CGFloat) -> SettingsPane? {
        let inner = barWidth - 8
        guard inner > 0 else { return nil }
        let index = Int(((x - 4) / inner * CGFloat(panes.count)).rounded(.down))
        return panes[min(max(index, 0), panes.count - 1)]
    }
}

extension View {
    /// Puts settings sections in the standard grouped form.
    func settingsPage() -> some View {
        Form { self }
            .formStyle(.grouped)
    }
}
