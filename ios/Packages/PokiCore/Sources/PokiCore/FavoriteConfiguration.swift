import Foundation

public struct FavoriteConfiguration: Codable, Equatable, Sendable {
    public var friendID: UUID
    public var message: String

    public init(friendID: UUID, message: String) {
        self.friendID = friendID
        self.message = message
    }
}

