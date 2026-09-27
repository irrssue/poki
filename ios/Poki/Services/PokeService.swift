import Foundation

protocol PokeService: Sendable {
    func sendPoke(to friendID: UUID, message: String) async throws
}

struct PreviewPokeService: PokeService {
    func sendPoke(to friendID: UUID, message: String) async throws {
        try await Task.sleep(for: .milliseconds(450))
    }
}

