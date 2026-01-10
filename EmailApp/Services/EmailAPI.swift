import Foundation

// MARK: - Email API Protocol

/// Protocol defining all email API operations
protocol EmailAPIProtocol {
    // Thread operations
    func listThreads(labelId: String, page: Int, pageSize: Int) async throws -> [EmailThread]
    func getThread(threadId: String) async throws -> EmailThread
    func applyAction(threadIds: [String], action: MessageAction) async throws

    // Label operations
    func listLabels() async throws -> [EmailLabel]
    func createLabel(name: String, color: String?) async throws -> EmailLabel
    func updateLabel(labelId: String, name: String?, color: String?) async throws -> EmailLabel
    func deleteLabel(labelId: String) async throws

    // Draft operations
    func createDraft(draft: EmailDraft) async throws -> EmailDraft
    func updateDraft(draft: EmailDraft) async throws -> EmailDraft
    func sendDraft(draftId: String) async throws
    func deleteDraft(draftId: String) async throws

    // Search operations
    func search(filters: EmailSearchFilters) async throws -> [EmailThread]

    // Attachment operations
    func uploadAttachment(data: Data, filename: String, mimeType: String) async throws -> EmailAttachment
    func downloadAttachment(attachmentId: String) async throws -> Data
}

// MARK: - Convex Email API Implementation

/// Implementation of EmailAPIProtocol using Convex HTTP actions
class ConvexEmailAPI: EmailAPIProtocol {
    // MARK: - Properties

    private let baseURL: URL
    private let session: URLSession
    private var authToken: String?

    // MARK: - Initialization

    init(
        baseURL: URL = URL(string: "https://your-convex-deployment.convex.cloud")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - Configuration

    func setAuthToken(_ token: String) {
        self.authToken = token
    }

    // MARK: - Thread Operations

    func listThreads(labelId: String, page: Int, pageSize: Int) async throws -> [EmailThread] {
        let endpoint = baseURL.appendingPathComponent("api/threads/list")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        let body: [String: Any] = [
            "labelId": labelId,
            "page": page,
            "pageSize": pageSize
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([EmailThread].self, from: data)
    }

    func getThread(threadId: String) async throws -> EmailThread {
        let endpoint = baseURL.appendingPathComponent("api/threads/get")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        let body: [String: Any] = ["threadId": threadId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(EmailThread.self, from: data)
    }

    func applyAction(threadIds: [String], action: MessageAction) async throws {
        let endpoint = baseURL.appendingPathComponent("api/threads/action")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        let body: [String: Any] = [
            "threadIds": threadIds,
            "action": action.rawValue
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    // MARK: - Label Operations

    func listLabels() async throws -> [EmailLabel] {
        let endpoint = baseURL.appendingPathComponent("api/labels/list")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        return try decoder.decode([EmailLabel].self, from: data)
    }

    func createLabel(name: String, color: String?) async throws -> EmailLabel {
        let endpoint = baseURL.appendingPathComponent("api/labels/create")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        var body: [String: Any] = ["name": name]
        if let color = color {
            body["color"] = color
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        return try decoder.decode(EmailLabel.self, from: data)
    }

    func updateLabel(labelId: String, name: String?, color: String?) async throws -> EmailLabel {
        let endpoint = baseURL.appendingPathComponent("api/labels/update")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        var body: [String: Any] = ["labelId": labelId]
        if let name = name { body["name"] = name }
        if let color = color { body["color"] = color }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        return try decoder.decode(EmailLabel.self, from: data)
    }

    func deleteLabel(labelId: String) async throws {
        let endpoint = baseURL.appendingPathComponent("api/labels/delete")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        let body: [String: Any] = ["labelId": labelId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    // MARK: - Draft Operations

    func createDraft(draft: EmailDraft) async throws -> EmailDraft {
        let endpoint = baseURL.appendingPathComponent("api/drafts/create")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(draft)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(EmailDraft.self, from: data)
    }

    func updateDraft(draft: EmailDraft) async throws -> EmailDraft {
        let endpoint = baseURL.appendingPathComponent("api/drafts/update")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(draft)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(EmailDraft.self, from: data)
    }

    func sendDraft(draftId: String) async throws {
        let endpoint = baseURL.appendingPathComponent("api/drafts/send")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        let body: [String: Any] = ["draftId": draftId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    func deleteDraft(draftId: String) async throws {
        let endpoint = baseURL.appendingPathComponent("api/drafts/delete")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        let body: [String: Any] = ["draftId": draftId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    // MARK: - Search Operations

    func search(filters: EmailSearchFilters) async throws -> [EmailThread] {
        let endpoint = baseURL.appendingPathComponent("api/search")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(filters)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([EmailThread].self, from: data)
    }

    // MARK: - Attachment Operations

    func uploadAttachment(data: Data, filename: String, mimeType: String) async throws -> EmailAttachment {
        let endpoint = baseURL.appendingPathComponent("api/attachments/upload")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        addAuthHeader(to: &request)

        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var bodyData = Data()
        bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
        bodyData.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        bodyData.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        bodyData.append(data)
        bodyData.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = bodyData

        let (responseData, response) = try await session.data(for: request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        return try decoder.decode(EmailAttachment.self, from: responseData)
    }

    func downloadAttachment(attachmentId: String) async throws -> Data {
        let endpoint = baseURL.appendingPathComponent("api/attachments/download")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        let body: [String: Any] = ["attachmentId": attachmentId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        return data
    }

    // MARK: - Private Helpers

    private func addAuthHeader(to request: inout URLRequest) {
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmailError.invalidData
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw EmailError.authenticationError
        case 404:
            throw EmailError.notFound
        case 429:
            throw EmailError.quotaExceeded
        default:
            throw EmailError.serverError(httpResponse.statusCode)
        }
    }
}

// MARK: - Mock Email API

/// Mock implementation for testing and development
class MockEmailAPI: EmailAPIProtocol {
    private var threads: [EmailThread] = EmailThread.mockThreads
    private var labels: [EmailLabel] = EmailLabel.allSystemLabels
    private var drafts: [EmailDraft] = []

    func listThreads(labelId: String, page: Int, pageSize: Int) async throws -> [EmailThread] {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 500_000_000)

        return threads.filter { thread in
            thread.labels.contains { $0.id == labelId }
        }
    }

    func getThread(threadId: String) async throws -> EmailThread {
        try await Task.sleep(nanoseconds: 300_000_000)

        guard let thread = threads.first(where: { $0.id == threadId }) else {
            throw EmailError.notFound
        }

        // Return with full messages
        var fullThread = thread
        if fullThread.messages.isEmpty {
            fullThread.messages = [.mock]
        }
        return fullThread
    }

    func applyAction(threadIds: [String], action: MessageAction) async throws {
        try await Task.sleep(nanoseconds: 200_000_000)

        for threadId in threadIds {
            guard let index = threads.firstIndex(where: { $0.id == threadId }) else {
                continue
            }

            switch action {
            case .markRead:
                threads[index].isRead = true
            case .markUnread:
                threads[index].isRead = false
            case .star:
                threads[index].isStarred = true
            case .unstar:
                threads[index].isStarred = false
            case .archive:
                threads[index].isArchived = true
            case .trash:
                threads[index].isTrashed = true
            case .spam:
                threads[index].isSpam = true
            default:
                break
            }
        }
    }

    func listLabels() async throws -> [EmailLabel] {
        try await Task.sleep(nanoseconds: 200_000_000)
        return labels
    }

    func createLabel(name: String, color: String?) async throws -> EmailLabel {
        try await Task.sleep(nanoseconds: 300_000_000)

        let label = EmailLabel(
            id: UUID().uuidString,
            name: name,
            type: .custom,
            color: color,
            unreadCount: 0,
            totalCount: 0,
            isHidden: false
        )
        labels.append(label)
        return label
    }

    func updateLabel(labelId: String, name: String?, color: String?) async throws -> EmailLabel {
        try await Task.sleep(nanoseconds: 200_000_000)

        guard let index = labels.firstIndex(where: { $0.id == labelId }) else {
            throw EmailError.notFound
        }

        // Labels are immutable, create a new one
        let oldLabel = labels[index]
        let updatedLabel = EmailLabel(
            id: oldLabel.id,
            name: name ?? oldLabel.name,
            type: oldLabel.type,
            color: color ?? oldLabel.color,
            unreadCount: oldLabel.unreadCount,
            totalCount: oldLabel.totalCount,
            isHidden: oldLabel.isHidden
        )
        labels[index] = updatedLabel
        return updatedLabel
    }

    func deleteLabel(labelId: String) async throws {
        try await Task.sleep(nanoseconds: 200_000_000)
        labels.removeAll { $0.id == labelId }
    }

    func createDraft(draft: EmailDraft) async throws -> EmailDraft {
        try await Task.sleep(nanoseconds: 300_000_000)

        var newDraft = draft
        if newDraft.id.isEmpty {
            newDraft = EmailDraft(
                id: UUID().uuidString,
                accountId: draft.accountId,
                replyToMessageId: draft.replyToMessageId,
                replyToThreadId: draft.replyToThreadId,
                recipients: draft.recipients,
                ccRecipients: draft.ccRecipients,
                bccRecipients: draft.bccRecipients,
                subject: draft.subject,
                body: draft.body,
                attachments: draft.attachments,
                createdAt: Date(),
                updatedAt: Date(),
                isDraft: true
            )
        }
        drafts.append(newDraft)
        return newDraft
    }

    func updateDraft(draft: EmailDraft) async throws -> EmailDraft {
        try await Task.sleep(nanoseconds: 200_000_000)

        guard let index = drafts.firstIndex(where: { $0.id == draft.id }) else {
            throw EmailError.notFound
        }

        drafts[index] = draft
        return draft
    }

    func sendDraft(draftId: String) async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
        drafts.removeAll { $0.id == draftId }
    }

    func deleteDraft(draftId: String) async throws {
        try await Task.sleep(nanoseconds: 200_000_000)
        drafts.removeAll { $0.id == draftId }
    }

    func search(filters: EmailSearchFilters) async throws -> [EmailThread] {
        try await Task.sleep(nanoseconds: 400_000_000)

        guard let query = filters.query, !query.isEmpty else {
            return []
        }

        let lowercaseQuery = query.lowercased()

        return threads.filter { thread in
            thread.subject.lowercased().contains(lowercaseQuery) ||
            thread.snippet.lowercased().contains(lowercaseQuery) ||
            thread.primarySender?.displayName.lowercased().contains(lowercaseQuery) ?? false ||
            thread.primarySender?.email.lowercased().contains(lowercaseQuery) ?? false
        }
    }

    func uploadAttachment(data: Data, filename: String, mimeType: String) async throws -> EmailAttachment {
        try await Task.sleep(nanoseconds: 500_000_000)

        return EmailAttachment(
            id: UUID().uuidString,
            filename: filename,
            mimeType: mimeType,
            size: Int64(data.count),
            downloadURL: nil,
            thumbnailURL: nil
        )
    }

    func downloadAttachment(attachmentId: String) async throws -> Data {
        try await Task.sleep(nanoseconds: 300_000_000)
        return Data()
    }
}

// MARK: - API Factory

/// Factory for creating appropriate API implementation
enum APIFactory {
    static func createEmailAPI() -> EmailAPIProtocol {
        #if DEBUG
        // Use mock API in debug builds
        return MockEmailAPI()
        #else
        // Use real Convex API in production
        return ConvexEmailAPI()
        #endif
    }
}
