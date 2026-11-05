import AppKit
import Observation
import SwiftUI

/// Routes menu bar and toast actions into the main Library or Settings workspace.
@Observable
final class MainWindowRouter {
    static let shared = MainWindowRouter()

    /// Library categories to show on arrival. The Library clears this after applying it.
    var pendingLibraryCategories: Set<LibraryViewModel.Category>?
    /// Counts requests from code that can't open windows itself, such as a toast's button.
    /// `WindowRequestPresenter` opens the window for each one.
    private(set) var openRequests = 0

    /// Brings the main window forward, opening it if needed. The app is activated too,
    /// since a menu bar app is often in the background.
    func show(libraryCategories: Set<LibraryViewModel.Category>? = nil, using openWindow: OpenWindowAction) {
        if let libraryCategories { showLibrary(categories: libraryCategories) }
        NSApplication.shared.activate()
        openWindow(id: WindowID.main)
    }

    /// Like `show(libraryCategories:using:)`, for code with no `openWindow` at hand.
    func request(libraryCategories: Set<LibraryViewModel.Category>? = nil) {
        if let libraryCategories { showLibrary(categories: libraryCategories) }
        openRequests += 1
    }

    /// Switches the main workspace to Library and applies the requested categories.
    private func showLibrary(categories: Set<LibraryViewModel.Category>) {
        pendingLibraryCategories = categories
        UserDefaults.standard.set(MainTab.library.rawValue, forKey: MainTab.storageKey)
    }

    /// Opens the Settings tab on `pane`, or the category last used when none is given.
    func showSettings(_ pane: SettingsPane? = nil, using openWindow: OpenWindowAction) {
        if let pane {
            UserDefaults.standard.set(pane.rawValue, forKey: SettingsPane.storageKey)
        }
        UserDefaults.standard.set(MainTab.settings.rawValue, forKey: MainTab.storageKey)
        NSApplication.shared.activate()
        openWindow(id: WindowID.main)
    }
}

/// Opens the main window whenever `MainWindowRouter.request` asks. It sits on the menu bar
/// icon, which exists for as long as the app runs.
struct WindowRequestPresenter: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onChange(of: MainWindowRouter.shared.openRequests) {
            MainWindowRouter.shared.show(using: openWindow)
        }
    }
}
