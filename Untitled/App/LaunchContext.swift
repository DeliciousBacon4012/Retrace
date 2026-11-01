import AppKit
import CoreServices
import Observation
import SwiftUI

/// Decides once per launch whether the main window opens. Untitled opens it when you start
/// the app yourself, if that's turned on, and stays in the menu bar when it starts at login.
@Observable
final class LaunchContext {
    /// Set when the main window should open: at launch, or from a Dock click with nothing
    /// open. Cleared once it has.
    var opensMainWindow = false

    /// Call from `applicationDidFinishLaunching(_:)`, while the launch's Apple event is current.
    func finishLaunching(opensWindowSetting: Bool) {
        let atLogin = Self.isLoginLaunch(NSAppleEventManager.shared().currentAppleEvent)
        opensMainWindow = opensWindowSetting && !atLogin
    }

    /// Login items are opened with an "open application" event marked as a login launch.
    private static func isLoginLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEOpenApplication)
        else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }
}

/// Opens the main window when the launch asks for it. It sits on the menu bar icon, which
/// is on screen for the app's whole life, so the request is seen whenever it arrives.
struct LaunchWindowPresenter: ViewModifier {
    let launch: LaunchContext
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.task(id: launch.opensMainWindow) {
            guard launch.opensMainWindow else { return }
            launch.opensMainWindow = false
            MainWindowRouter.shared.show(using: openWindow)
        }
    }
}
