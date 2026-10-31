import Observation

/// Lets places outside the main window, such as the menu bar, choose which page it shows
/// the next time it appears.
@Observable
final class MainWindowRouter {
    static let shared = MainWindowRouter()

    /// A page to switch to. The main window clears it once shown.
    var pending: AppTab?
}
