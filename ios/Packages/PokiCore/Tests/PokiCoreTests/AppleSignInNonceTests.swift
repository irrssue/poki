import XCTest
@testable import PokiCore

final class AppleSignInNonceTests: XCTestCase {
    func testHashIsLowercaseSHA256OfRawValue() {
        XCTAssertEqual(AppleSignInNonce(raw: "abc").hashed, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testGeneratedNoncesAreLongAndUnique() {
        let first = AppleSignInNonce(), second = AppleSignInNonce()
        XCTAssertEqual(first.raw.count, 64)
        XCTAssertNotEqual(first.raw, second.raw)
        XCTAssertNotEqual(first.raw, first.hashed)
    }
}
