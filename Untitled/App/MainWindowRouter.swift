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

    /// Brings the main window forward, opening it if needed, on `page` if one is given.
    /// The app is activated too, since a menu bar app is often in the background.
    func show(_ page: AppTab? = nil, using openWindow: OpenWindowAction) {
        if let page { pending = page }
        openWindow(id: WindowID.main)
        NSApplication.shared.activate()
    }
}
