import Observation

/// State for the main window: which sidebar row is selected.
@Observable
final class MainViewModel {
    var selection: SidebarItem? = .home
}
