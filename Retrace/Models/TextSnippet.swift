import Foundation

/// Text that Capture Text read and copied.
nonisolated struct TextSnippet: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let text: String
    let date: Date

    /// The first line with words in it, shortened to fit a menu.
    var summary: String {
        let line = text.split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return line.count > 48 ? String(line.prefix(47)) + "…" : line
    }

    var lineCount: Int {
        text.split(whereSeparator: \.isNewline).count
    }
}
