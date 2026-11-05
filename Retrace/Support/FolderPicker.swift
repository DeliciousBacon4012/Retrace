import AppKit

/// Shows the standard open panel for choosing one folder.
enum FolderPicker {
    /// Returns the chosen folder, or `nil` if the person cancelled.
    static func chooseFolder(startingAt directory: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose")
        panel.directoryURL = directory
        return panel.runModal() == .OK ? panel.url : nil
    }
}
