import Observation

/// State for the main window: which tab is showing.
@Observable
final class MainViewModel {
    var selectedTab: AppTab = .home
}
