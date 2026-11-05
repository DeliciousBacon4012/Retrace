import AppKit
import Observation
import SwiftUI

/// Lets places outside the main window, such as the menu bar and toasts, open it or the
/// Settings window, on the Recents filter or Settings tab they need.
@Observable
final class MainWindowRouter {
    static let shared = MainWindowRouter()

    /// A Recents filter to switch to. The main window clears it once applied.
    var pendingRecentsFilter: LibraryViewModel.KindFilter?
    /// Counts requests from code that can't open windows itself, such as a toast's button.
    /// `WindowRequestPresenter` opens the window for each one.
    private(set) var openRequests = 0

    /// Brings the main window forward, opening it if needed. The app is activated too,
    /// since a menu bar app is often in the background.
    func show(recentsFilter: LibraryViewModel.KindFilter? = nil, using openWindow: OpenWindowAction) {
        if let recentsFilter { showCaptures(filter: recentsFilter) }
        NSApplication.shared.activate()
        openWindow(id: WindowID.main)
    }

    /// Like `show(recentsFilter:using:)`, for code with no `openWindow` at hand.
    func request(recentsFilter: LibraryViewModel.KindFilter? = nil) {
        if let recentsFilter { showCaptures(filter: recentsFilter) }
        openRequests += 1
    }

    /// Switches the window to captures, with this filter.
    private func showCaptures(filter: LibraryViewModel.KindFilter) {
        pendingRecentsFilter = filter
        UserDefaults.standard.set(MainSection.captures.rawValue, forKey: MainSection.storageKey)
    }

    /// Opens Settings, on `pane` if one is given, otherwise on the category last used.
    /// Activating first brings the window in front even while retrace has no Dock icon.
    func showSettings(_ pane: SettingsPane? = nil, using openSettings: OpenSettingsAction) {
        if let pane {
            UserDefaults.standard.set(pane.rawValue, forKey: SettingsPane.storageKey)
        }
        NSApplication.shared.activate()
        openSettings()
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
