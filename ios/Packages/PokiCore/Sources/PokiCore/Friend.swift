import Foundation

public struct Friend: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var username: String
    public var avatarSystemName: String

    public init(
        id: UUID = UUID(),
        name: String,
        username: String,
        avatarSystemName: String = "person.crop.circle.fill"
    ) {
        self.id = id
        self.name = name
        self.username = username
        self.avatarSystemName = avatarSystemName
    }
}

public extension Friend {
    static let previews: [Friend] = [
        Friend(name: "Sam", username: "sam", avatarSystemName: "face.smiling.inverse"),
        Friend(name: "Maya", username: "maya", avatarSystemName: "person.crop.circle.fill"),
        Friend(name: "Alex", username: "alex", avatarSystemName: "person.circle.fill")
    ]
}

