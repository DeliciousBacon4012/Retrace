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
        guard stroke.count >= 2 else { return nil }

        // This runs for every pointer update. Collect the bounds and median input in one
        // pass instead of allocating separate coordinate arrays for each bound.
        var minX = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var minY = CGFloat.infinity
        var maxY = -CGFloat.infinity
        var yValues: [CGFloat] = []
        yValues.reserveCapacity(stroke.count)
        for point in stroke {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
            yValues.append(point.y)
        }
        guard maxX - minX >= 4 else { return nil }

        // The median ignores a hook at either end of the stroke.
        yValues.sort()
        let middleY = yValues[yValues.count / 2]

        var nearestLine: TextLine?
        var nearestDistance = CGFloat.infinity
        for line in lines {
            let height = line.rect.height
            let slack = height * 0.35
            guard middleY >= line.rect.minY - slack,
                  middleY <= line.rect.maxY + slack,
                  maxY - minY <= height * 1.6,
                  line.rect.minX < maxX,
                  line.rect.maxX > minX
            else { continue }

            let distance = abs(line.rect.midY - middleY)
            if distance < nearestDistance {
                nearestLine = line
                nearestDistance = distance
            }
        }
        guard let line = nearestLine else { return nil }

        // Whole words: a word counts once the stroke crosses about a third of it.
        var left: CGFloat?
        var right: CGFloat?
        for word in line.words {
            let overlap = min(maxX, word.maxX) - max(minX, word.minX)
            guard overlap >= word.width * 0.3 else { continue }
            left = min(left ?? word.minX, word.minX)
            right = max(right ?? word.maxX, word.maxX)
        }
        let bandLeft = left ?? max(minX, line.rect.minX)
        let bandRight = right ?? min(maxX, line.rect.maxX)
        guard bandRight > bandLeft else { return nil }

        return band(for: line, from: bandLeft, to: bandRight)
    }

    /// One band per line of text inside `box`, top to bottom, covering the whole words the box
    /// reaches on each line. Empty when the box holds no text. Used by Shift-drag, which
    /// highlights a block of lines at once.
    static func bands(in box: CGRect, lines: [TextLine]) -> [Band] {
        guard box.width >= 2, box.height >= 2 else { return [] }
        var result: [(top: CGFloat, band: Band)] = []
        result.reserveCapacity(lines.count)
        for line in lines {
            // Most of the line's height must be inside the box, so a box edge grazing the
            // line above or below doesn't pull it in.
            let vertical = min(box.maxY, line.rect.maxY) - max(box.minY, line.rect.minY)
            guard vertical >= line.rect.height * 0.4,
                  line.rect.minX < box.maxX,
                  line.rect.maxX > box.minX
            else { continue }

            var left: CGFloat?
            var right: CGFloat?
            for word in line.words {
                let overlap = min(box.maxX, word.maxX) - max(box.minX, word.minX)
                guard overlap >= word.width * 0.3 else { continue }
                left = min(left ?? word.minX, word.minX)
                right = max(right ?? word.maxX, word.maxX)
            }
            guard let left, let right, right > left else { continue }
            result.append((line.rect.minY, band(for: line, from: left, to: right)))
        }
        result.sort { $0.top < $1.top }
        return result.map { $0.band }
    }

    private static func band(for line: TextLine, from left: CGFloat, to right: CGFloat) -> Band {
        let height = line.rect.height
        let padding = height * 0.12
        return Band(
            start: CGPoint(x: left - padding, y: line.rect.midY),
            end: CGPoint(x: right + padding, y: line.rect.midY),
            thickness: height * 1.1
        )
    }
}
