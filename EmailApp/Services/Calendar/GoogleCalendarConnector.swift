import Foundation
import AuthenticationServices

final class GoogleCalendarConnector: NSObject, ObservableObject {
    @Published var isConnected: Bool = false
    @Published var connectedEmail: String?
    @Published var isAuthenticating: Bool = false
    @Published var error: String?

    private let brainWorkerBaseURL: URL
    private var webAuthSession: ASWebAuthenticationSession?
    private var clerkUserId: String

    init(brainWorkerBaseURL: URL, clerkUserId: String) {
        self.brainWorkerBaseURL = brainWorkerBaseURL
        self.clerkUserId = clerkUserId
        super.init()
    }

    @MainActor
    func startOAuthFlow(presentingWindow: ASPresentationAnchor) async throws {
        isAuthenticating = true
        error = nil

        defer { isAuthenticating = false }

        // Get auth URL from worker
        var urlComponents = URLComponents(url: brainWorkerBaseURL.appendingPathComponent("/oauth/google/start"), resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [URLQueryItem(name: "user", value: clerkUserId)]

        let (data, _) = try await URLSession.shared.data(from: urlComponents.url!)

        struct StartResponse: Codable {
            let authUrl: String
            let state: String
        }

        let response = try JSONDecoder().decode(StartResponse.self, from: data)

        guard let authURL = URL(string: response.authUrl) else {
            throw NSError(domain: "GoogleCalendar", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid auth URL"])
        }

        // Start web auth session
        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "orion-calendar"
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: NSError(domain: "GoogleCalendar", code: 2, userInfo: [NSLocalizedDescriptionKey: "No callback URL"]))
                    return
                }
                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false

            self.webAuthSession = session
            session.start()
        }

        // Parse the callback - in production, the worker handles this
        // The web auth session will redirect back after the worker processes the callback

        // For now, check connection status
        try await checkConnectionStatus()
    }

    @MainActor
    func checkConnectionStatus() async throws {
        // Check with worker if we have valid tokens
        var urlComponents = URLComponents(url: brainWorkerBaseURL.appendingPathComponent("/sync/google/status"), resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [URLQueryItem(name: "user", value: clerkUserId)]

        do {
            let (data, _) = try await URLSession.shared.data(from: urlComponents.url!)
            struct StatusResponse: Codable {
                let connected: Bool
                let email: String?
            }
            let response = try JSONDecoder().decode(StatusResponse.self, from: data)
            isConnected = response.connected
            connectedEmail = response.email
        } catch {
            // If status endpoint doesn't exist, assume not connected
            isConnected = false
            connectedEmail = nil
        }
    }

    @MainActor
    func triggerSync() async throws -> Int {
        var urlComponents = URLComponents(url: brainWorkerBaseURL.appendingPathComponent("/sync/google/run"), resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [URLQueryItem(name: "user", value: clerkUserId)]

        let (data, response) = try await URLSession.shared.data(from: urlComponents.url!)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "GoogleCalendar", code: 3, userInfo: [NSLocalizedDescriptionKey: "Sync failed"])
        }

        struct SyncResponse: Codable {
            let ok: Bool
            let synced: Int
        }

        let syncResult = try JSONDecoder().decode(SyncResponse.self, from: data)
        return syncResult.synced
    }

    @MainActor
    func disconnect() async throws {
        var urlComponents = URLComponents(url: brainWorkerBaseURL.appendingPathComponent("/sync/google/disconnect"), resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [URLQueryItem(name: "user", value: clerkUserId)]

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "POST"

        _ = try await URLSession.shared.data(for: request)

        isConnected = false
        connectedEmail = nil
    }
}

extension GoogleCalendarConnector: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }
}
