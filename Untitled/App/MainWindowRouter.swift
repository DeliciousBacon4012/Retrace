import AppKit
import Observation
import SwiftUI

/// Lets places outside the main window, such as the menu bar and the Settings command,
/// choose which page it shows the next time it appears.
@Observable
final class MainWindowRouter {
    static let shared = MainWindowRouter()

    /// A page to switch to. The main window clears it once shown.
    var pending: AppTab?
    /// A Recents filter to switch to. Recents clears it once applied.
    var pendingRecentsFilter: LibraryViewModel.KindFilter?
    /// Counts requests from code that can't open windows itself, such as a toast's button.
    /// `WindowRequestPresenter` opens the window for each one.
    private(set) var openRequests = 0

    /// Brings the main window forward, opening it if needed, on `page` if one is given.
    /// The app is activated too, since a menu bar app is often in the background.
    func show(_ page: AppTab? = nil, recentsFilter: LibraryViewModel.KindFilter? = nil, using openWindow: OpenWindowAction) {
        if let page { pending = page }
        if let recentsFilter { pendingRecentsFilter = recentsFilter }
        openWindow(id: WindowID.main)
        NSApplication.shared.activate()
    }

    /// Like `show(_:recentsFilter:using:)`, for code with no `openWindow` at hand.
    func request(_ page: AppTab? = nil, recentsFilter: LibraryViewModel.KindFilter? = nil) {
        if let page { pending = page }
        if let recentsFilter { pendingRecentsFilter = recentsFilter }
        openRequests += 1
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
