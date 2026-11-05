import Foundation
import OSLog

/// Writes captures to disk with names built from the filename template.
protocol CaptureStoring: AnyObject {
    /// Saves the data in `folder`, creating it if needed, and returns the new file's URL.
    func save(_ data: Data, template: String, date: Date, fileExtension: String, in folder: URL) throws -> URL
    /// Returns a free file URL in `folder` for something written later, such as a recording.
    func reserveURL(template: String, date: Date, fileExtension: String, in folder: URL) throws -> URL
}

final class FileCaptureStorage: CaptureStoring {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func save(_ data: Data, template: String, date: Date, fileExtension: String, in folder: URL) throws -> URL {
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let baseName = FileNameTemplate.fileName(from: template, date: date)
        let url = uniqueURL(in: folder, baseName: baseName, fileExtension: fileExtension)
        try data.write(to: url, options: .atomic)
        Log.capture.info("Saved capture to \(url.path, privacy: .private)")
        return url
    }

    func reserveURL(template: String, date: Date, fileExtension: String, in folder: URL) throws -> URL {
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let baseName = FileNameTemplate.fileName(from: template, date: date)
        return uniqueURL(in: folder, baseName: baseName, fileExtension: fileExtension)
    }

    /// Adds " 2", " 3", and so on until the name is free, so nothing is overwritten.
    private func uniqueURL(in folder: URL, baseName: String, fileExtension: String) -> URL {
        CaptureURLReservationRegistry.shared.uniqueURL(in: folder, baseName: baseName, fileExtension: fileExtension)
    }
}

/// Fills in `{date}` and `{time}` in a filename template.
nonisolated enum FileNameTemplate {
    static func fileName(from template: String, date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH.mm.ss"

        let filled = template
            .replacingOccurrences(of: "{date}", with: dateFormatter.string(from: date))
            .replacingOccurrences(of: "{time}", with: timeFormatter.string(from: date))
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return filled.isEmpty ? "retrace" : filled
    }
}
