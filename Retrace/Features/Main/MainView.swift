import AppKit
import SwiftUI

/// The main window: Library and Editor, one two-finger swipe apart.
struct MainView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        MainContent(access: ScreenRecordingAccessModel(permissions: dependencies.permissions))
    }
}

enum MainTab: String, CaseIterable, Identifiable {
    case library
    case editor

    var id: String { rawValue }
    var title: String {
        switch self {
        case .library: String(localized: "Library")
        case .editor: String(localized: "Editor")
        }
    }
    static let storageKey = "mainWindowTab"
}

private struct MainContent: View {
    @State var access: ScreenRecordingAccessModel
    @State private var library = LibraryViewModel()
    @AppStorage(MainTab.storageKey) private var tab: MainTab = .library

    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        VStack(spacing: 0) {
            if access.screenRecording == .notGranted {
                PermissionBanner(model: access)
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 2)
                    .transition(.opacity)
            }

            PagedTabs(selection: $tab, pages: MainTab.allCases) { page in
                switch page {
                case .library: LibraryView(viewModel: library)
                case .editor: EditorLandingView()
                }
            }
        }
        // On a view that exists only for the Library, so the field leaves the toolbar with it.
        .background {
            if tab == .library {
                Color.clear.searchable(text: $library.searchText, prompt: "Search Library")
            }
        }
        .navigationTitle(tab.title)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Workspace", selection: $tab) {
                    ForEach(MainTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .tabPickerStyle()
                .labelsHidden()
                .fixedSize()
                .help("Switch tabs, or swipe with two fingers")
            }

            if tab == .library {
                ToolbarItem(placement: .primaryAction) {
                    LibraryFilterControl(selection: $library.selectedCategories, sortOrder: $library.sortOrder)
                }
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                CaptureMenu()
                RecordControl()
            }
        }
        .frame(minWidth: 800, minHeight: 520)
        .animation(.panel, value: access.screenRecording)
        .task {
            await access.watchScreenRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            access.refresh()
        }
    }

}

/// One native filter menu contains multi-select categories and date ordering.
private struct LibraryFilterControl: View {
    @Binding var selection: Set<LibraryViewModel.Category>
    @Binding var sortOrder: LibraryViewModel.SortOrder

    private var isFiltering: Bool { selection.count < LibraryViewModel.Category.allCases.count }

    var body: some View {
        Menu {
            Section("Show") {
                ForEach(LibraryViewModel.Category.allCases) { category in
                    Toggle(category.title, systemImage: category.symbolName, isOn: Binding(
                        get: { selection.contains(category) },
                        set: { isOn in
                            if isOn {
                                selection.insert(category)
                            } else {
                                selection.remove(category)
                            }
                        }
                    ))
                }
                Button("Show All") {
                    selection = Set(LibraryViewModel.Category.allCases)
                }
            }
            Picker("Sort by", selection: $sortOrder) {
                ForEach(LibraryViewModel.SortOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
        } label: {
            Label("Filter", systemImage: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                .labelStyle(.iconOnly)
                .contentTransition(.symbolEffect(.replace))
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Filter and Sort Library")
        .accessibilityValue(Text("\(selection.count) filters, \(sortOrder.title)"))
        .help("Filter and sort Library items")
    }
}

/// One toolbar button opens the menu of capture modes; no split arrow or second click target.
private struct CaptureMenu: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(SettingsStore.self) private var settings

    private var saveFolder: URL? {
        CaptureDestinationSelection.folder(for: settings.captureDestinationOverridePath, in: settings)
    }

    private var destinationName: String {
        let activePath = CaptureDestinationSelection.activePath(for: settings.captureDestinationOverridePath, in: settings)
        return settings.saveFolderDisplayName(for: activePath)
    }

    var body: some View {
        Menu {
            if settings.saveFolderPaths.count > 1 {
                CaptureDestinationOptions()
                Divider()
            }
            ForEach(QuickAction.all.filter { $0.captureMode != nil }) { action in
                CaptureButton(action: action, saveFolder: saveFolder)
            }
        } label: {
            Label("Capture", systemImage: "viewfinder")
                .labelStyle(.titleAndIcon)
        }
        .menuIndicator(.hidden)
        .id(settings.captureDestinationOverridePath)
        .disabled(dependencies.capture.isCapturing)
        .accessibilityValue(Text(destinationName))
        .help("Choose Area, Window, or Full Screen capture. Saves to \(destinationName).")
    }
}

/// One screenshot mode. The menu names each action and its shortcut.
private struct CaptureButton: View {
    let action: QuickAction
    let saveFolder: URL?

    @Environment(AppDependencies.self) private var dependencies
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Button(action.title, systemImage: action.symbolName) {
            Task { await dependencies.capture.run(action, savingTo: saveFolder) }
        }
        .help(helpText)
        .disabled(dependencies.capture.isCapturing)
    }

    private var helpText: String {
        guard let shortcut = settings.shortcuts[action.id] else { return action.title }
        return "\(action.title)  \(shortcut.displayString)"
    }
}

/// Native menu toggles identify the active destination and share it across capture and recording.
private struct CaptureDestinationOptions: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Section("Save to") {
            ForEach(settings.saveFolderPaths, id: \.self) { path in
                Toggle(settings.saveFolderDisplayName(for: path), isOn: Binding(
                    get: {
                        path == CaptureDestinationSelection.activePath(
                            for: settings.captureDestinationOverridePath,
                            in: settings
                        )
                    },
                    set: { _ in
                        settings.captureDestinationOverridePath = CaptureDestinationSelection.selection(
                            for: path,
                            defaultPath: settings.saveFolderPath
                        )
                    }
                ))
                .toggleStyle(.checkbox)
                .accessibilityValue(Text(
                    path == CaptureDestinationSelection.activePath(for: settings.captureDestinationOverridePath, in: settings)
                        ? "Selected"
                        : "Not selected"
                ))
                .help(path)
            }
        }
    }
}

/// Record uses the same single-button menu as Capture; its modes are direct and discoverable.
private struct RecordControl: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(SettingsStore.self) private var settings

    private var saveFolder: URL? {
        CaptureDestinationSelection.folder(for: settings.captureDestinationOverridePath, in: settings)
    }

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
            .buttonStyle(.glassProminent)
            .tint(.red)
            .disabled(recording.recorder.state == .finishing)
            .help("Stop Recording")
        } else {
            Menu {
                if settings.saveFolderPaths.count > 1 {
                    CaptureDestinationOptions()
                    Divider()
                }
                ForEach(QuickAction.recordings) { action in
                    RecordingActionButton(action: action, saveFolder: saveFolder)
                        .menuShortcut(settings.shortcuts[action.id])
                }
                Divider()
                Toggle("Replay Buffer", isOn: Binding(
                    get: { settings.replayBufferEnabled },
                    set: { dependencies.replay.setEnabled($0) }
                ))
                SaveLastMenu(saveFolder: saveFolder)
            } label: {
                Label(
                    "Record",
                    systemImage: dependencies.replay.buffer.isOn ? "record.circle.fill" : "record.circle"
                )
                .labelStyle(.titleAndIcon)
            }
            .menuIndicator(.hidden)
            .id(settings.captureDestinationOverridePath)
            .help(recordHelp)
            .disabled(recording.recorder.state != .idle)
        }
    }

    private var recordHelp: String {
        let base = String(localized: "Choose Area, Window, or Full Screen recording.")
        return dependencies.replay.buffer.isOn ? base + " " + String(localized: "Replay buffer is on.") : base
    }
}

private struct RecordingActionButton: View {
    let action: QuickAction
    let saveFolder: URL?

    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        Button(action.title, systemImage: action.symbolName) {
            guard let mode = action.recordingMode else { return }
            Task { await dependencies.recording.toggle(mode, savingTo: saveFolder) }
        }
        .disabled(dependencies.recording.recorder.state != .idle)
    }
}

#if DEBUG
#Preview("Library") {
    let dependencies = MainViewPreview.makeDependencies()
    MainView()
        .environment(dependencies)
        .environment(dependencies.settings)
        .frame(width: 1_180, height: 760)
}

#Preview("Minimum Window") {
    let dependencies = MainViewPreview.makeDependencies()
    MainView()
        .environment(dependencies)
        .environment(dependencies.settings)
        .frame(width: 800, height: 520)
}

#Preview("Empty Library") {
    let dependencies = AppDependencies.preview(screenRecording: .granted)
    MainView()
        .environment(dependencies)
        .environment(dependencies.settings)
        .frame(width: 800, height: 520)
}

@MainActor
private enum MainViewPreview {
    static func makeDependencies() -> AppDependencies {
        let dependencies = AppDependencies.preview(screenRecording: .granted)

        let folder = FileManager.default.temporaryDirectory
            .appending(path: "Retrace-Library-Preview", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let samples: [(String, Int, Int, CGColor)] = [
            ("Sample Capture — Landscape.png", 1200, 760, CGColor(red: 0.96, green: 0.62, blue: 0.31, alpha: 1)),
            ("Sample Capture — Portrait.png", 720, 1080, CGColor(red: 0.20, green: 0.47, blue: 0.54, alpha: 1)),
            ("Sample Capture — Editor.png", 1200, 760, CGColor(red: 0.10, green: 0.13, blue: 0.18, alpha: 1)),
            ("Sample Capture — Browser.png", 1280, 800, CGColor(red: 0.39, green: 0.67, blue: 0.57, alpha: 1)),
            ("Sample Capture — Notes.png", 760, 1080, CGColor(red: 0.78, green: 0.50, blue: 0.37, alpha: 1)),
            ("Sample Capture — Window.png", 960, 720, CGColor(red: 0.43, green: 0.56, blue: 0.78, alpha: 1)),
            ("Sample Capture — Reference.png", 1200, 760, CGColor(red: 0.71, green: 0.68, blue: 0.48, alpha: 1)),
            ("Sample Capture — Article.png", 1200, 760, CGColor(red: 0.64, green: 0.45, blue: 0.72, alpha: 1))
        ]
        for (name, width, height, color) in samples {
            let url = folder.appending(path: name)
            guard !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { continue }
            writeSampleImage(at: url, width: width, height: height, color: color)
        }
        let now = Date.now
        dependencies.library.setPreviewItems(samples.enumerated().map { index, sample in
            let url = folder.appending(path: sample.0)
            let byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return LibraryItem(
                url: url,
                date: now.addingTimeInterval(-Double(index) * 1_800),
                modified: now,
                kind: .image,
                byteCount: byteCount
            )
        })
        return dependencies
    }

    private static func writeSampleImage(at url: URL, width: Int, height: Int, color: CGColor) {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let margin = CGFloat(width) * 0.07
        let titleHeight = CGFloat(height) * 0.10
        let card = CGRect(x: margin, y: margin, width: CGFloat(width) - margin * 2, height: CGFloat(height) - margin * 2)
        context.setFillColor(CGColor(gray: 1, alpha: 0.90))
        context.fill(card)
        context.setFillColor(CGColor(gray: 0.12, alpha: 0.86))
        context.fill(CGRect(x: card.minX, y: card.maxY - titleHeight, width: card.width, height: titleHeight))
        context.setFillColor(CGColor(gray: 1, alpha: 0.58))
        for line in 0..<5 {
            let y = card.maxY - titleHeight - CGFloat(line + 1) * card.height * 0.11
            context.fill(CGRect(x: card.minX + card.width * 0.06, y: y, width: card.width * (line.isMultiple(of: 2) ? 0.76 : 0.52), height: max(2, CGFloat(height) * 0.009)))
        }
        if let image = context.makeImage(),
           let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
    }
}
#endif
