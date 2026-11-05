import XCTest
@testable import Untitled

final class OCRTextFormattingTests: XCTestCase {
    func testCopiedTextPreservesRecognizedLineBreaksByDefault() {
        let content = RecognizedContent(lines: [
            .init(text: "  First line  ", rect: .zero),
            .init(text: "Second line", rect: .zero),
        ])

        XCTAssertEqual(content.copiedText(preservingLineBreaks: true), "First line\nSecond line")
    }

    func testCopiedTextCanJoinRecognizedLinesIntoAParagraph() {
        let content = RecognizedContent(lines: [
            .init(text: "First line", rect: .zero),
            .init(text: " Second line ", rect: .zero),
        ])

        XCTAssertEqual(content.copiedText(preservingLineBreaks: false), "First line Second line")
    }

    func testCodesUseTheSameFormattingPreference() {
        let content = RecognizedContent(codes: ["https://example.com", "ABCD"])

        XCTAssertEqual(content.copiedText(preservingLineBreaks: false), "https://example.com ABCD")
    }

    func testCodesAreUsedWhenRecognizedLinesContainOnlyWhitespace() {
        let content = RecognizedContent(
            lines: [.init(text: " \n ", rect: .zero)],
            codes: ["https://example.com"]
        )

        XCTAssertEqual(content.copiedText(preservingLineBreaks: true), "https://example.com")
    }

    func testWhitespaceOnlyTextIsTreatedAsEmpty() {
        let content = RecognizedContent(lines: [
            .init(text: " \n ", rect: .zero),
        ])

        XCTAssertTrue(content.isEmpty)
        XCTAssertEqual(content.copiedText(preservingLineBreaks: true), "")
    }
}
