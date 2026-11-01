import CoreGraphics

/// Turns a rough highlighter stroke along a line of text into a clean band over the words
/// it covers, the height of the text, like a marker pulled along a ruler.
nonisolated enum HighlightSnapping {
    struct Band: Equatable {
        var start: CGPoint
        var end: CGPoint
        var thickness: CGFloat
    }

    /// The band for `stroke`, or `nil` when the stroke doesn't follow a single line of text,
    /// such as a circle or a stroke down a paragraph, which stay freehand.
    static func band(for stroke: [CGPoint], lines: [TextLine]) -> Band? {
        guard stroke.count >= 2,
              let minX = stroke.map(\.x).min(), let maxX = stroke.map(\.x).max(),
              let minY = stroke.map(\.y).min(), let maxY = stroke.map(\.y).max(),
              maxX - minX >= 4
        else { return nil }
        // The median ignores a hook at either end of the stroke.
        let middleY = stroke.map(\.y).sorted()[stroke.count / 2]

        let candidates = lines.filter { line in
            let height = line.rect.height
            let slack = height * 0.35
            return middleY >= line.rect.minY - slack
                && middleY <= line.rect.maxY + slack
                && maxY - minY <= height * 1.6
                && line.rect.minX < maxX && line.rect.maxX > minX
        }
        guard let line = candidates.min(by: { abs($0.rect.midY - middleY) < abs($1.rect.midY - middleY) }) else {
            return nil
        }

        // Whole words: a word counts once the stroke crosses about a third of it.
        let touched = line.words.filter { word in
            let overlap = min(maxX, word.maxX) - max(minX, word.minX)
            return overlap >= word.width * 0.3
        }
        let left = touched.map(\.minX).min() ?? max(minX, line.rect.minX)
        let right = touched.map(\.maxX).max() ?? min(maxX, line.rect.maxX)
        guard right > left else { return nil }

        let height = line.rect.height
        let padding = height * 0.12
        return Band(
            start: CGPoint(x: left - padding, y: line.rect.midY),
            end: CGPoint(x: right + padding, y: line.rect.midY),
            thickness: height * 1.1
        )
    }
}
