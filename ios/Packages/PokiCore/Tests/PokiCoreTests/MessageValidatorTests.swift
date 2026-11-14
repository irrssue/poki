import XCTest
@testable import PokiCore

final class MessageValidatorTests: XCTestCase {
    private struct Fixtures: Decodable {
        struct Case: Decodable { let text: String; let visible: Int }
        let maximumVisible: Int
        let maximumCodePoints: Int
        let cases: [Case]
    }

    private let family = "👨‍👩‍👧‍👦"

    func testEmptyMessageUsesDefault() {
        XCTAssertEqual(MessageValidator.resolvedMessage(from: "   "), "Thinking of you")
    }

    func testVisibleCharactersRespectLimit() {
        XCTAssertTrue(MessageValidator.isValid(String(repeating: "a", count: 30)))
        XCTAssertFalse(MessageValidator.isValid(String(repeating: "a", count: 31)))
    }

    func testComposedEmojiCountsAsOneVisibleCharacter() {
        XCTAssertEqual(MessageValidator.remainingCharacters(for: family), 29)
        XCTAssertTrue(MessageValidator.isValid(String(repeating: family, count: 30)))
        XCTAssertFalse(MessageValidator.isValid(String(repeating: family, count: 31)))
    }

    func testCodePointCapBoundsPayloads() {
        XCTAssertFalse(MessageValidator.isValid(String(repeating: "e\u{301}\u{301}\u{301}", count: 70)))
    }

    func testSharedFixturesMatchServerAndGraphemeCounts() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/message-length.json")
        let fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixtures.maximumVisible, MessageValidator.maximumLength)
        XCTAssertEqual(fixtures.maximumCodePoints, MessageValidator.maximumCodePoints)
        for fixture in fixtures.cases {
            XCTAssertEqual(MessageValidator.visibleLength(fixture.text), fixture.visible, fixture.text)
            XCTAssertEqual(fixture.text.count, fixture.visible, "grapheme count of \(fixture.text)")
        }
    }

    func testControlCharactersAreRejected() {
        XCTAssertFalse(MessageValidator.isValid("hi\u{0000}"))
        XCTAssertFalse(MessageValidator.isValid("hi\tthere"))
    }

    func testLineBreaksAreRejected() {
        XCTAssertFalse(MessageValidator.isValid("hello\nthere"))
    }
}
