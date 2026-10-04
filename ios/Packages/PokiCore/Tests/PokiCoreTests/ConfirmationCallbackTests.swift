import Foundation
import XCTest
@testable import PokiCore

final class ConfirmationCallbackTests: XCTestCase {
    func testSignupCallbackExtractsRefreshToken() throws {
        let url = URL(string: ConfirmationCallback.redirectURL + "#type=signup&refresh_token=synthetic-token&access_token=unused")!
        XCTAssertEqual(try ConfirmationCallback(url: url).refreshToken, "synthetic-token")
    }

    func testRejectsUnexpectedRoutesAndMalformedCredentials() {
        for value in [
            "https://example.com/auth/confirm#type=signup&refresh_token=test",
            "com.pokiapp.poki://other/confirm#type=signup&refresh_token=test",
            "com.pokiapp.poki://auth/other#type=signup&refresh_token=test",
            "com.pokiapp.poki://auth/confirm?type=signup&refresh_token=test",
            ConfirmationCallback.redirectURL + "#type=recovery&refresh_token=test",
            ConfirmationCallback.redirectURL + "#type=signup&refresh_token=",
            ConfirmationCallback.redirectURL + "#type=signup&refresh_token=a&refresh_token=b",
            ConfirmationCallback.redirectURL + "#error=access_denied&error_code=otp_expired"
        ] {
            XCTAssertThrowsError(try ConfirmationCallback(url: URL(string: value)!))
        }
    }
}
