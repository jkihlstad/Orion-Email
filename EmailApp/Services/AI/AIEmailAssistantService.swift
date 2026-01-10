//
//  AIEmailAssistantService.swift
//  EmailApp
//
//  AI service implementation that calls Brain/server endpoints
//

import Foundation
import Combine
import os.log

// MARK: - Logger

private let aiLogger = Logger(subsystem: "com.orion.emailapp", category: "AIAssistant")

// MARK: - AI Email Assistant Service

/// Implementation of AI email assistant using Brain/server endpoints
@MainActor
public final class AIEmailAssistantService: ObservableObject, AIEmailAssistantProtocol, @unchecked Sendable {
    // MARK: - Published Properties

    @Published public private(set) var processingState: AIProcessingState = .idle
    @Published public private(set) var lastError: AIError?

    // MARK: - Private Properties

    private let apiClient: BrainAPIClient
    private let consentManager: ConsentManagerProtocol
    private let cacheManager: AICacheManager
    private weak var delegate: AIEmailAssistantDelegate?

    // MARK: - Initialization

    public init(
        apiClient: BrainAPIClient,
        consentManager: ConsentManagerProtocol = ConsentManager.shared,
        cacheManager: AICacheManager = AICacheManager(),
        delegate: AIEmailAssistantDelegate? = nil
    ) {
        self.apiClient = apiClient
        self.consentManager = consentManager
        self.cacheManager = cacheManager
        self.delegate = delegate
    }

    /// Convenience initializer with default configuration
    public convenience init(
        authProvider: AuthSessionProviding,
        configuration: BrainAPIConfiguration = .default
    ) {
        let client = BrainAPIClient(configuration: configuration, authProvider: authProvider)
        self.init(apiClient: client)
    }

    // MARK: - AIEmailAssistantProtocol

    /// Summarize an email thread
    public nonisolated func summarizeThread(threadId: String) async throws -> ThreadSummary {
        // Check consent
        try await checkConsent(for: .aiAnalysis)

        await updateState(.processing(operation: "Summarizing thread"))

        // Check cache first
        if let cached = await cacheManager.getCachedSummary(threadId: threadId) {
            aiLogger.debug("Returning cached summary for thread: \(threadId)")
            await updateState(.completed)
            return cached
        }

        do {
            let request = SummarizeRequest(threadId: threadId)
            let response: SummarizeResponse = try await apiClient.post(
                endpoint: .summarize,
                body: request
            )

            let summary = ThreadSummary(
                id: response.id ?? UUID().uuidString,
                threadId: threadId,
                summary: response.summary,
                keyPoints: response.keyPoints,
                sentiment: Sentiment(rawValue: response.sentiment) ?? .neutral,
                urgency: UrgencyLevel(rawValue: response.urgency) ?? .medium
            )

            // Cache the result
            await cacheManager.cacheSummary(summary, threadId: threadId)

            await updateState(.completed)
            aiLogger.info("Successfully summarized thread: \(threadId)")

            return summary

        } catch let error as BrainAPIError {
            await handleError(mapBrainError(error))
            throw mapBrainError(error)
        } catch {
            let aiError = AIError.unknown(message: error.localizedDescription)
            await handleError(aiError)
            throw aiError
        }
    }

    /// Suggest replies for a specific message
    public nonisolated func suggestReplies(messageId: String) async throws -> [SuggestedReply] {
        try await checkConsent(for: .aiAnalysis)

        await updateState(.processing(operation: "Generating reply suggestions"))

        // Check cache
        if let cached = await cacheManager.getCachedReplies(messageId: messageId) {
            aiLogger.debug("Returning cached replies for message: \(messageId)")
            await updateState(.completed)
            return cached
        }

        do {
            let request = SuggestRepliesRequest(messageId: messageId)
            let response: SuggestRepliesResponse = try await apiClient.post(
                endpoint: .suggestReplies,
                body: request
            )

            let replies = response.suggestions.map { suggestion in
                SuggestedReply(
                    id: suggestion.id ?? UUID().uuidString,
                    text: suggestion.text,
                    tone: ReplyTone(rawValue: suggestion.tone) ?? .professional,
                    confidence: suggestion.confidence ?? 0.8
                )
            }

            await cacheManager.cacheReplies(replies, messageId: messageId)

            await updateState(.completed)
            aiLogger.info("Generated \(replies.count) reply suggestions for message: \(messageId)")

            return replies

        } catch let error as BrainAPIError {
            await handleError(mapBrainError(error))
            throw mapBrainError(error)
        } catch {
            let aiError = AIError.unknown(message: error.localizedDescription)
            await handleError(aiError)
            throw aiError
        }
    }

    /// Extract tasks from a message
    public nonisolated func extractTasks(messageId: String) async throws -> [ExtractedTask] {
        try await checkConsent(for: .aiAnalysis)

        await updateState(.processing(operation: "Extracting tasks"))

        // Check cache
        if let cached = await cacheManager.getCachedTasks(messageId: messageId) {
            aiLogger.debug("Returning cached tasks for message: \(messageId)")
            await updateState(.completed)
            return cached
        }

        do {
            let request = ExtractTasksRequest(messageId: messageId)
            let response: ExtractTasksResponse = try await apiClient.post(
                endpoint: .extractTasks,
                body: request
            )

            let tasks = response.tasks.map { task in
                ExtractedTask(
                    id: task.id ?? UUID().uuidString,
                    messageId: messageId,
                    description: task.description,
                    dueDate: task.dueDate,
                    priority: TaskPriority(rawValue: task.priority ?? "medium") ?? .medium,
                    assignee: task.assignee,
                    confidence: task.confidence ?? 0.8
                )
            }

            await cacheManager.cacheTasks(tasks, messageId: messageId)

            await updateState(.completed)
            aiLogger.info("Extracted \(tasks.count) tasks from message: \(messageId)")

            return tasks

        } catch let error as BrainAPIError {
            await handleError(mapBrainError(error))
            throw mapBrainError(error)
        } catch {
            let aiError = AIError.unknown(message: error.localizedDescription)
            await handleError(aiError)
            throw aiError
        }
    }

    /// Ask a question about an email
    public nonisolated func askAboutEmail(messageId: String, question: String) async throws -> AIResponse {
        try await checkConsent(for: .aiAnalysis)

        await updateState(.processing(operation: "Analyzing email"))

        do {
            let request = AskQuestionRequest(messageId: messageId, question: question)
            let response: AskQuestionResponse = try await apiClient.post(
                endpoint: .askQuestion,
                body: request
            )

            let sources = response.sources?.map { source in
                AISource(
                    id: source.id ?? UUID().uuidString,
                    messageId: source.messageId ?? messageId,
                    snippet: source.snippet,
                    relevanceScore: source.relevanceScore ?? 0.8
                )
            } ?? []

            let aiResponse = AIResponse(
                id: response.id ?? UUID().uuidString,
                answer: response.answer,
                sources: sources,
                confidence: response.confidence ?? 0.8
            )

            await updateState(.completed)
            aiLogger.info("Answered question about message: \(messageId)")

            return aiResponse

        } catch let error as BrainAPIError {
            await handleError(mapBrainError(error))
            throw mapBrainError(error)
        } catch {
            let aiError = AIError.unknown(message: error.localizedDescription)
            await handleError(aiError)
            throw aiError
        }
    }

    /// Get related memories for context
    public nonisolated func getRelatedMemories(messageId: String) async throws -> [MemoryChip] {
        try await checkConsent(for: .aiAnalysis)

        await updateState(.processing(operation: "Finding related memories"))

        // Check cache
        if let cached = await cacheManager.getCachedMemories(messageId: messageId) {
            aiLogger.debug("Returning cached memories for message: \(messageId)")
            await updateState(.completed)
            return cached
        }

        do {
            let queryItems = [URLQueryItem(name: "message_id", value: messageId)]
            let response: RelatedMemoriesResponse = try await apiClient.get(
                endpoint: .relatedMemories,
                queryItems: queryItems
            )

            let memories = response.memories.map { memory in
                MemoryChip(
                    id: memory.id ?? UUID().uuidString,
                    title: memory.title,
                    snippet: memory.snippet,
                    relevanceScore: memory.relevanceScore ?? 0.5,
                    memoryType: MemoryType(rawValue: memory.memoryType ?? "general") ?? .general,
                    sourceDate: memory.sourceDate,
                    metadata: memory.metadata
                )
            }

            await cacheManager.cacheMemories(memories, messageId: messageId)

            await updateState(.completed)
            aiLogger.info("Found \(memories.count) related memories for message: \(messageId)")

            return memories

        } catch let error as BrainAPIError {
            await handleError(mapBrainError(error))
            throw mapBrainError(error)
        } catch {
            let aiError = AIError.unknown(message: error.localizedDescription)
            await handleError(aiError)
            throw aiError
        }
    }

    // MARK: - Helper Methods

    /// Check consent before performing AI operations
    private nonisolated func checkConsent(for type: ConsentType) async throws {
        let hasConsent = await consentManager.hasConsent(for: type)

        if !hasConsent {
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.delegate?.assistant(self, requiresConsentFor: type)
            }
            throw AIError.noConsent(type)
        }
    }

    /// Update processing state
    private func updateState(_ state: AIProcessingState) async {
        await MainActor.run {
            self.processingState = state

            if case .processing = state {
                self.delegate?.assistantDidStartProcessing(self)
            } else if case .completed = state {
                self.delegate?.assistantDidFinishProcessing(self)
            }
        }
    }

    /// Handle error
    private func handleError(_ error: AIError) async {
        await MainActor.run {
            self.lastError = error
            self.processingState = .failed(error: error.localizedDescription ?? "Unknown error")
            self.delegate?.assistant(self, didEncounterError: error)
        }

        aiLogger.error("AI operation failed: \(error.localizedDescription ?? "Unknown")")
    }

    /// Map Brain API errors to AI errors
    private nonisolated func mapBrainError(_ error: BrainAPIError) -> AIError {
        switch error {
        case .unauthorized:
            return .unauthorized
        case .rateLimited(let retryAfter):
            return .rateLimited(retryAfter: retryAfter)
        case .networkError(let underlying):
            return .networkError(underlying: underlying)
        case .decodingError(let underlying):
            return .decodingError(underlying: underlying)
        case .serverError(let code, let message):
            return .serverError(statusCode: code, message: message)
        case .serviceUnavailable:
            return .serviceUnavailable
        default:
            return .unknown(message: error.localizedDescription ?? "Unknown error")
        }
    }
}

// MARK: - API Request/Response Models

/// Request to summarize a thread
private struct SummarizeRequest: Encodable {
    let threadId: String
}

/// Response from summarize endpoint
private struct SummarizeResponse: Decodable {
    let id: String?
    let summary: String
    let keyPoints: [String]
    let sentiment: String
    let urgency: String
}

/// Request for reply suggestions
private struct SuggestRepliesRequest: Encodable {
    let messageId: String
    let maxSuggestions: Int = 3
}

/// Response from suggest replies endpoint
private struct SuggestRepliesResponse: Decodable {
    let suggestions: [SuggestionData]

    struct SuggestionData: Decodable {
        let id: String?
        let text: String
        let tone: String
        let confidence: Float?
    }
}

/// Request for task extraction
private struct ExtractTasksRequest: Encodable {
    let messageId: String
}

/// Response from extract tasks endpoint
private struct ExtractTasksResponse: Decodable {
    let tasks: [TaskData]

    struct TaskData: Decodable {
        let id: String?
        let description: String
        let dueDate: Date?
        let priority: String?
        let assignee: String?
        let confidence: Float?
    }
}

/// Request for asking a question
private struct AskQuestionRequest: Encodable {
    let messageId: String
    let question: String
}

/// Response from ask question endpoint
private struct AskQuestionResponse: Decodable {
    let id: String?
    let answer: String
    let sources: [SourceData]?
    let confidence: Float?

    struct SourceData: Decodable {
        let id: String?
        let messageId: String?
        let snippet: String
        let relevanceScore: Float?
    }
}

/// Response from related memories endpoint
private struct RelatedMemoriesResponse: Decodable {
    let memories: [MemoryData]

    struct MemoryData: Decodable {
        let id: String?
        let title: String
        let snippet: String
        let relevanceScore: Float?
        let memoryType: String?
        let sourceDate: Date?
        let metadata: [String: String]?
    }
}

// MARK: - AI Cache Manager

/// Manager for caching AI results
public actor AICacheManager {
    private var summaryCache: [String: (ThreadSummary, Date)] = [:]
    private var repliesCache: [String: ([SuggestedReply], Date)] = [:]
    private var tasksCache: [String: ([ExtractedTask], Date)] = [:]
    private var memoriesCache: [String: ([MemoryChip], Date)] = [:]

    private let cacheExpiration: TimeInterval

    public init(cacheExpiration: TimeInterval = 300) { // 5 minutes default
        self.cacheExpiration = cacheExpiration
    }

    func getCachedSummary(threadId: String) -> ThreadSummary? {
        guard let (summary, date) = summaryCache[threadId] else { return nil }
        guard Date().timeIntervalSince(date) < cacheExpiration else {
            summaryCache.removeValue(forKey: threadId)
            return nil
        }
        return summary
    }

    func cacheSummary(_ summary: ThreadSummary, threadId: String) {
        summaryCache[threadId] = (summary, Date())
    }

    func getCachedReplies(messageId: String) -> [SuggestedReply]? {
        guard let (replies, date) = repliesCache[messageId] else { return nil }
        guard Date().timeIntervalSince(date) < cacheExpiration else {
            repliesCache.removeValue(forKey: messageId)
            return nil
        }
        return replies
    }

    func cacheReplies(_ replies: [SuggestedReply], messageId: String) {
        repliesCache[messageId] = (replies, Date())
    }

    func getCachedTasks(messageId: String) -> [ExtractedTask]? {
        guard let (tasks, date) = tasksCache[messageId] else { return nil }
        guard Date().timeIntervalSince(date) < cacheExpiration else {
            tasksCache.removeValue(forKey: messageId)
            return nil
        }
        return tasks
    }

    func cacheTasks(_ tasks: [ExtractedTask], messageId: String) {
        tasksCache[messageId] = (tasks, Date())
    }

    func getCachedMemories(messageId: String) -> [MemoryChip]? {
        guard let (memories, date) = memoriesCache[messageId] else { return nil }
        guard Date().timeIntervalSince(date) < cacheExpiration else {
            memoriesCache.removeValue(forKey: messageId)
            return nil
        }
        return memories
    }

    func cacheMemories(_ memories: [MemoryChip], messageId: String) {
        memoriesCache[messageId] = (memories, Date())
    }

    func clearCache() {
        summaryCache.removeAll()
        repliesCache.removeAll()
        tasksCache.removeAll()
        memoriesCache.removeAll()
    }
}

// MARK: - Mock Implementation

#if DEBUG
/// Mock AI assistant for testing and previews
@MainActor
public final class MockAIEmailAssistantService: ObservableObject, AIEmailAssistantProtocol, @unchecked Sendable {
    @Published public var processingState: AIProcessingState = .idle
    public var shouldFail = false
    public var delay: TimeInterval = 0.5

    public init() {}

    public nonisolated func summarizeThread(threadId: String) async throws -> ThreadSummary {
        try await simulateProcessing()

        return ThreadSummary(
            threadId: threadId,
            summary: "This is a mock summary of the email thread discussing project updates and next steps.",
            keyPoints: [
                "Project deadline extended to next Friday",
                "Team meeting scheduled for Monday",
                "Budget approved for new features"
            ],
            sentiment: .positive,
            urgency: .medium
        )
    }

    public nonisolated func suggestReplies(messageId: String) async throws -> [SuggestedReply] {
        try await simulateProcessing()

        return [
            SuggestedReply(
                text: "Thank you for the update. I'll review the details and get back to you shortly.",
                tone: .professional
            ),
            SuggestedReply(
                text: "Got it, thanks! Let me know if you need anything else.",
                tone: .casual
            ),
            SuggestedReply(
                text: "Acknowledged.",
                tone: .brief
            )
        ]
    }

    public nonisolated func extractTasks(messageId: String) async throws -> [ExtractedTask] {
        try await simulateProcessing()

        return [
            ExtractedTask(
                messageId: messageId,
                description: "Review project proposal",
                dueDate: Date().addingTimeInterval(86400 * 2),
                priority: .high
            ),
            ExtractedTask(
                messageId: messageId,
                description: "Schedule follow-up meeting",
                dueDate: Date().addingTimeInterval(86400),
                priority: .medium
            )
        ]
    }

    public nonisolated func askAboutEmail(messageId: String, question: String) async throws -> AIResponse {
        try await simulateProcessing()

        return AIResponse(
            answer: "Based on the email, the answer to '\(question)' is: This appears to be related to the ongoing project discussions.",
            sources: [
                AISource(
                    messageId: messageId,
                    snippet: "...relevant section from the email...",
                    relevanceScore: 0.95
                )
            ],
            confidence: 0.85
        )
    }

    public nonisolated func getRelatedMemories(messageId: String) async throws -> [MemoryChip] {
        try await simulateProcessing()

        return [
            MemoryChip(
                title: "Previous Discussion",
                snippet: "Last week's email about the same topic...",
                relevanceScore: 0.9,
                memoryType: .email
            ),
            MemoryChip(
                title: "Contact Info",
                snippet: "John Smith - Project Manager",
                relevanceScore: 0.7,
                memoryType: .contact
            )
        ]
    }

    private nonisolated func simulateProcessing() async throws {
        let delay = await MainActor.run { self.delay }
        let shouldFail = await MainActor.run { self.shouldFail }

        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        if shouldFail {
            throw AIError.serviceUnavailable
        }
    }
}
#endif
