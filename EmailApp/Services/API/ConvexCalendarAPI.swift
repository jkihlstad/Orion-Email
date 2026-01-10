import Foundation

final class ConvexCalendarAPI {
    private let baseURL: URL
    private let auth: ClerkSessionProviding

    init(baseURL: URL, auth: ClerkSessionProviding) {
        self.baseURL = baseURL
        self.auth = auth
    }

    private func makeRequest(_ path: String, method: String, body: Data?) async throws -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let token = try await auth.getBearerToken()
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }

    func listEvents(startAt: Date, endAt: Date) async throws -> [CalendarEventDTO] {
        let payload: [String: Any] = ["startAt": Int(startAt.timeIntervalSince1970 * 1000),
                                     "endAt": Int(endAt.timeIntervalSince1970 * 1000)]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let req = try await makeRequest("/calendar/events/list", method: "POST", body: data)
        let (resData, _) = try await URLSession.shared.data(for: req)

        struct Resp: Codable { let events: [ConvexEventWire] }
        let decoded = try JSONDecoder().decode(Resp.self, from: resData)
        return decoded.events.map { $0.toDTO() }
    }

    func updatePolicy(eventId: String, policy: EventPolicy) async throws {
        let encoder = JSONEncoder()
        let policyData = try encoder.encode(policy)
        let policyObj = try JSONSerialization.jsonObject(with: policyData) as! [String: Any]
        let payload: [String: Any] = ["eventId": eventId, "policy": policyObj]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let req = try await makeRequest("/calendar/events/updatePolicy", method: "POST", body: data)
        _ = try await URLSession.shared.data(for: req)
    }

    func listProposals(status: String = "sent") async throws -> [RescheduleProposalDTO] {
        var components = URLComponents(url: baseURL.appendingPathComponent("/calendar/proposals/list"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "status", value: status)]
        var req = URLRequest(url: components.url!)
        req.httpMethod = "GET"
        let token = try await auth.getBearerToken()
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: req)
        struct Wire: Codable { let proposals: [ConvexProposalWire] }
        let decoded = try JSONDecoder().decode(Wire.self, from: data)
        return decoded.proposals.map { $0.toDTO() }
    }

    func applyProposal(proposalId: String) async throws {
        let payload: [String: Any] = ["proposalId": proposalId]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let req = try await makeRequest("/calendar/proposals/apply", method: "POST", body: data)
        _ = try await URLSession.shared.data(for: req)
    }
}

// MARK: - Wire models
private struct ConvexEventWire: Codable {
    let _id: String
    let title: String?
    let startAt: Int
    let endAt: Int
    let timezone: String
    let policy: ConvexPolicyWire?

    func toDTO() -> CalendarEventDTO {
        CalendarEventDTO(
            id: _id,
            title: title,
            startAt: TimeInterval(startAt) / 1000,
            endAt: TimeInterval(endAt) / 1000,
            timezone: timezone,
            policy: policy?.toPolicy()
        )
    }
}

private struct ConvexPolicyWire: Codable {
    let lockState: String
    let requiresUserConfirmationBeforeSendingRequests: Bool
    let contentSharing: String
    let approver: ConvexApproverWire?

    func toPolicy() -> EventPolicy {
        EventPolicy(
            lockState: LockState(rawValue: lockState) ?? .flexible,
            requiresUserConfirmationBeforeSendingRequests: requiresUserConfirmationBeforeSendingRequests,
            contentSharing: contentSharing,
            approver: approver?.toApprover(),
            maxShiftMinutes: nil,
            maxShiftDays: nil
        )
    }
}

private struct ConvexApproverWire: Codable {
    let name: String?
    let email: String?
    let phone: String?

    func toApprover() -> EventApprover {
        EventApprover(name: name, email: email, phone: phone)
    }
}

private struct ConvexProposalWire: Codable {
    let _id: String
    let eventId: String
    let status: String
    let rationale: String
    let options: [ProposalOptionDTO]
    let chosenOptionIndex: Int?
    let requiresApprover: Bool

    func toDTO() -> RescheduleProposalDTO {
        RescheduleProposalDTO(
            id: _id,
            eventId: eventId,
            status: status,
            rationale: rationale,
            options: options,
            chosenOptionIndex: chosenOptionIndex,
            requiresApprover: requiresApprover
        )
    }
}
