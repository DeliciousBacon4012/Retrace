import AppKit
import SwiftUI

/// The main window: your captures as the content, with capture, record, filter and
/// Settings on the window toolbar, which macOS draws as Liquid Glass over them.
/// There's no sidebar; settings live in their own window.
struct MainView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        MainContent(access: ScreenRecordingAccessModel(permissions: dependencies.permissions))
    }
}

private struct MainContent: View {
    @State var access: ScreenRecordingAccessModel
    @State private var library = LibraryViewModel()

    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        LibraryView(viewModel: library)
            .safeAreaInset(edge: .top, spacing: 0) {
                if access.screenRecording == .notGranted {
                    PermissionBanner(model: access)
                        .padding([.horizontal, .top], 16)
                        .padding(.bottom, 4)
                        .transition(.opacity)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    ForEach(QuickAction.screenshots) { action in
                        CaptureButton(action: action)
                    }
                }
                ToolbarSpacer(.fixed, placement: .navigation)
                ToolbarItem(placement: .navigation) {
                    RecordControl()
                }
                ToolbarItem(placement: .primaryAction) {
                    FilterMenu(viewModel: library)
                }
                ToolbarItem(placement: .primaryAction) {
                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Settings  ⌘,")
                }
            }
            .frame(minWidth: 520, minHeight: 340)
            .animation(.panel, value: access.screenRecording)
            .task {
                await access.watchScreenRecording()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                access.refresh()
            }
    }
}

/// One screenshot mode. The toolbar shows its symbol; the tooltip names it and its shortcut.
private struct CaptureButton: View {
    let action: QuickAction

    @Environment(AppDependencies.self) private var dependencies
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Button(action.title, systemImage: action.symbolName) {
            Task { await dependencies.capture.run(action) }
        }
        .help(helpText)
        .disabled(dependencies.capture.isCapturing)
    }

    private var helpText: String {
        guard let shortcut = settings.shortcuts[action.id] else { return action.title }
        return "\(action.title)  \(shortcut.displayString)"
    }
}

/// Click to record an area; the menu holds the other recordings and the replay buffer.
/// While recording, it becomes the one red Stop button.
private struct RecordControl: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        let recording = dependencies.recording
        if recording.countdown != nil {
            Button("Cancel Recording", systemImage: "xmark") {
                recording.cancelCountdown()
            }
            .help("Cancel the countdown")
        } else if recording.isRecording {
            Button("Stop Recording", systemImage: "stop.fill") {
                recording.recorder.stop()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(recording.recorder.state == .finishing)
            .help("Stop Recording")
        } else {
            Menu {
                ForEach(QuickAction.recordings) { action in
                    QuickActionButton(action: action)
                        .menuShortcut(settings.shortcuts[action.id])
                }
                Divider()
                Toggle("Replay Buffer", isOn: Binding(
                    get: { settings.replayBufferEnabled },
                    set: { dependencies.replay.setEnabled($0) }
                ))
                SaveLastMenu()
            } label: {
                Label("Record", systemImage: dependencies.replay.buffer.isOn ? "record.circle.fill" : "record.circle")
            } primaryAction: {
                Task { await recording.toggle(.area) }
            }
            .help(recordHelp)
            .disabled(recording.recorder.state != .idle)
        }
    }

    private var recordHelp: String {
        let base = String(localized: "Record Area. Open the menu for more.")
        return dependencies.replay.buffer.isOn ? base + " " + String(localized: "Replay buffer is on.") : base
    }
}

/// Which captures show, plus the save folder. The symbol fills in while a filter is on.
private struct FilterMenu: View {
    @Bindable var viewModel: LibraryViewModel

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Menu {
            Picker("Show", selection: $viewModel.kindFilter) {
                ForEach(LibraryViewModel.KindFilter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Show Save Folder in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([settings.saveFolderURL])
            }
        } label: {
            Label(
                "Filter",
                systemImage: viewModel.kindFilter == .all
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill"
            )
        }
        .help(viewModel.kindFilter == .all ? String(localized: "Show All") : String(localized: "Showing \(viewModel.kindFilter.title)"))
    }
}

#if DEBUG
#Preview {
    let dependencies = AppDependencies.preview(screenRecording: .granted)
    MainView()
        .environment(dependencies)
        .environment(dependencies.settings)
        .frame(width: 600, height: 440)
}
#endif
