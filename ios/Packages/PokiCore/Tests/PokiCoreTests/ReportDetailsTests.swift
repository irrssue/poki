import XCTest
@testable import PokiCore

final class ReportDetailsTests: XCTestCase {
    func testLineBreaksAndControlsBecomeSpaces() {
        XCTAssertEqual(ReportDetails.normalized("  sent\nthis\tagain\u{0000} "), "sent this again")
    }

    func testJoinedEmojiArePreserved() {
        XCTAssertEqual(ReportDetails.normalized("👨‍👩‍👧‍👦"), "👨‍👩‍👧‍👦")
    }

    func testLimitMatchesDatabaseCodePointBudget() {
        XCTAssertTrue(ReportDetails.isValid(String(repeating: "a", count: 300)))
        XCTAssertFalse(ReportDetails.isValid(String(repeating: "a", count: 301)))
        XCTAssertTrue(ReportDetails.isValid(" " + String(repeating: "a", count: 300) + "\n"))
        XCTAssertEqual(ReportDetails.remainingCharacters(for: "👨‍👩‍👧‍👦"), 293)
    }
}
