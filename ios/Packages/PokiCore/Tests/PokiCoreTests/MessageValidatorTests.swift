import XCTest
@testable import PokiCore

final class MessageValidatorTests: XCTestCase {
    func testEmptyMessageUsesDefault() {
        XCTAssertEqual(MessageValidator.resolvedMessage(from: "   "), "Thinking of you")
    }

    func testVisibleCharactersRespectLimit() {
        XCTAssertTrue(MessageValidator.isValid(String(repeating: "a", count: 30)))
        XCTAssertFalse(MessageValidator.isValid(String(repeating: "a", count: 31)))
    }

    func testComposedEmojiCountsAsOneCharacter() {
        let family = "👨‍👩‍👧‍👦"
        XCTAssertEqual(family.count, 1)
        XCTAssertEqual(MessageValidator.remainingCharacters(for: family), 29)
    }

    func testLineBreaksAreRejected() {
        XCTAssertFalse(MessageValidator.isValid("hello\nthere"))
    }
}
