import Foundation

protocol ClerkSessionProviding {
    func getBearerToken() async throws -> String
}

final class ClerkSessionProvider: ClerkSessionProviding {
    private let devUserId: String
    private let role: String

    init(devUserId: String = "user_123", role: String = "user") {
        self.devUserId = devUserId
        self.role = role
    }

    func getBearerToken() async throws -> String {
        return "dev:\(devUserId):\(role)"
    }
}
