import XCTest

final class TextPostprocessorTests: XCTestCase {
    func testTrimsAndCollapsesWhitespace() {
        let input = "  Привет,   это   тест.  \n\n  Вторая строка.  "
        XCTAssertEqual(TextPostprocessor.clean(input), "Привет, это тест. Вторая строка.")
    }

    func testRemovesZeroWidthSpaces() {
        let input = "При\u{200B}вет"
        XCTAssertEqual(TextPostprocessor.clean(input), "Привет")
    }

    func testFiltersKnownHallucination() {
        XCTAssertEqual(TextPostprocessor.clean("Спасибо за просмотр!"), "")
        XCTAssertEqual(TextPostprocessor.clean("продолжение следует…"), "")
        XCTAssertEqual(TextPostprocessor.clean("Thank you for watching."), "")
    }

    func testKeepsLegitimateTextContainingHallucinationWords() {
        let text = "Спасибо за просмотр фильма, было интересно"
        XCTAssertEqual(TextPostprocessor.clean(text), text)
    }

    func testFiltersSubtitleHallucinations() {
        XCTAssertEqual(TextPostprocessor.clean("Субтитры сделал DimaTorzok"), "")
        XCTAssertEqual(TextPostprocessor.clean("Редактор субтитров А.Синецкая"), "")
        XCTAssertEqual(TextPostprocessor.clean("Дякую за перегляд!"), "")
    }

    func testKeepsLongTextWithMarker() {
        let text = String(repeating: "Подписывайтесь на канал, но сначала послушайте важную новость. ", count: 3)
        XCTAssertFalse(TextPostprocessor.clean(text).isEmpty)
    }

    func testEmptyInput() {
        XCTAssertEqual(TextPostprocessor.clean("   \n  "), "")
    }
}
