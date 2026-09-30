import PokiCore
import XCTest
@testable import Poki

@MainActor
final class AppModelTests: XCTestCase {
    func testSuccessfulSendClearsDraft() async {
        let model = AppModel(pokeService: PreviewPokeService())
        model.friends = Friend.previews
        let friend = model.friends[0]
        model.updateDraft("Miss you", for: friend)

        await model.send(to: friend)

        XCTAssertEqual(model.drafts[friend.id], "")
        XCTAssertEqual(model.feedback, SendFeedback(friendName: friend.name, succeeded: true))
    }

    func testInvalidDraftIsNotStored() {
        let model = AppModel(pokeService: PreviewPokeService())
        model.friends = Friend.previews
        let friend = model.friends[0]
        model.updateDraft(String(repeating: "x", count: 31), for: friend)

        XCTAssertNil(model.drafts[friend.id])
    }
}
