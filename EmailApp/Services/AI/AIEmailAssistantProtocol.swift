//
//  AIEmailAssistantProtocol.swift
//  EmailApp
//
//  Protocol definition for AI email assistant functionality
//

import Foundation

// MARK: - AI Email Assistant Protocol

/// Protocol defining the AI email assistant capabilities
public protocol AIEmailAssistantProtocol: AnyObject, Sendable {
    /// Summarize an email thread
    /// - Parameter threadId: The ID of the thread to summarize
    /// - Returns: A summary of the thread including key points, sentiment, and urgency
    /// - Throws: AIError if the operation fails
    func summarizeThread(threadId: String) async throws -> ThreadSummary

    /// Suggest replies for a specific message
    /// - Parameter messageId: The ID of the message to generate replies for
    /// - Returns: An array of suggested replies with different tones
    /// - Throws: AIError if the operation fails
    func suggestReplies(messageId: String) async throws -> [SuggestedReply]

    /// Extract tasks from a message
    /// - Parameter messageId: The ID of the message to extract tasks from
    /// - Returns: An array of extracted tasks with descriptions and due dates
    /// - Throws: AIError if the operation fails
    func extractTasks(messageId: String) async throws -> [ExtractedTask]

    /// Ask a question about an email
    /// - Parameters:
    ///   - messageId: The ID of the message to query
    ///   - question: The question to ask about the email
    /// - Returns: An AI response with the answer and source references
    /// - Throws: AIError if the operation fails
    func askAboutEmail(messageId: String, question: String) async throws -> AIResponse

    /// Get related memories for context
    /// - Parameter messageId: The ID of the message to find related memories for
    /// - Returns: An array of memory chips with relevant context
    /// - Throws: AIError if the operation fails
    func getRelatedMemories(messageId: String) async throws -> [MemoryChip]
}

// MARK: - Extended Protocol with Optional Features

/// Extended protocol with additional optional features
public protocol AIEmailAssistantExtendedProtocol: AIEmailAssistantProtocol {
    /// Generate a draft reply based on intent
    /// - Parameters:
    ///   - messageId: The ID of the message to reply to
    ///   - intent: The user's intent for the reply (e.g., "accept meeting", "decline politely")
    ///   - tone: The desired tone for the reply
    /// - Returns: A generated reply draft
    func generateDraft(messageId: String, intent: String, tone: ReplyTone) async throws -> SuggestedReply

    /// Analyze email for priority and categorization
    /// - Parameter messageId: The ID of the message to analyze
    /// - Returns: Analysis results including priority, category, and action items
    func analyzeEmail(messageId: String) async throws -> EmailAnalysis

    /// Batch summarize multiple threads
    /// - Parameter threadIds: Array of thread IDs to summarize
    /// - Returns: Dictionary mapping thread IDs to their summaries
    func batchSummarize(threadIds: [String]) async throws -> [String: ThreadSummary]
}

// MARK: - Email Analysis Result

/// Result of email analysis
public struct EmailAnalysis: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let messageId: String
    public let priority: TaskPriority
    public let category: EmailCategory
    public let actionItems: [String]
    public let requiresResponse: Bool
    public let suggestedDeadline: Date?
    public let sentiment: Sentiment
    public let confidence: Float
    public let analyzedAt: Date

    public init(
        id: String = UUID().uuidString,
        messageId: String,
        priority: TaskPriority,
        category: EmailCategory,
        actionItems: [String] = [],
        requiresResponse: Bool = false,
        suggestedDeadline: Date? = nil,
        sentiment: Sentiment = .neutral,
        confidence: Float = 0.8,
        analyzedAt: Date = Date()
    ) {
        self.id = id
        self.messageId = messageId
        self.priority = priority
        self.category = category
        self.actionItems = actionItems
        self.requiresResponse = requiresResponse
        self.suggestedDeadline = suggestedDeadline
        self.sentiment = sentiment
        self.confidence = confidence
        self.analyzedAt = analyzedAt
    }
}

/// Email category classification
public enum EmailCategory: String, Codable, CaseIterable, Sendable {
    case work
    case personal
    case newsletter
    case promotional
    case social
    case transactional
    case support
    case spam
    case other

    public var displayName: String {
        switch self {
        case .work: return "Work"
        case .personal: return "Personal"
        case .newsletter: return "Newsletter"
        case .promotional: return "Promotional"
        case .social: return "Social"
        case .transactional: return "Transactional"
        case .support: return "Support"
        case .spam: return "Spam"
        case .other: return "Other"
        }
    }

    public var systemImageName: String {
        switch self {
        case .work: return "briefcase"
        case .personal: return "person"
        case .newsletter: return "newspaper"
        case .promotional: return "tag"
        case .social: return "person.2"
        case .transactional: return "creditcard"
        case .support: return "questionmark.circle"
        case .spam: return "xmark.bin"
        case .other: return "tray"
        }
    }
}

// MARK: - AI Assistant Delegate

/// Delegate for receiving AI assistant events
public protocol AIEmailAssistantDelegate: AnyObject {
    /// Called when AI processing begins
    func assistantDidStartProcessing(_ assistant: AIEmailAssistantProtocol)

    /// Called when AI processing completes
    func assistantDidFinishProcessing(_ assistant: AIEmailAssistantProtocol)

    /// Called when an error occurs
    func assistant(_ assistant: AIEmailAssistantProtocol, didEncounterError error: AIError)

    /// Called when consent is required
    func assistant(_ assistant: AIEmailAssistantProtocol, requiresConsentFor type: ConsentType)
}

// MARK: - Default Delegate Implementation

public extension AIEmailAssistantDelegate {
    func assistantDidStartProcessing(_ assistant: AIEmailAssistantProtocol) {}
    func assistantDidFinishProcessing(_ assistant: AIEmailAssistantProtocol) {}
    func assistant(_ assistant: AIEmailAssistantProtocol, didEncounterError error: AIError) {}
    func assistant(_ assistant: AIEmailAssistantProtocol, requiresConsentFor type: ConsentType) {}
}

// MARK: - AI Request Context

/// Context information for AI requests
public struct AIRequestContext: Sendable {
    public let userId: String?
    public let threadId: String?
    public let messageId: String?
    public let includeHistory: Bool
    public let maxTokens: Int?
    public let temperature: Float?

    public init(
        userId: String? = nil,
        threadId: String? = nil,
        messageId: String? = nil,
        includeHistory: Bool = true,
        maxTokens: Int? = nil,
        temperature: Float? = nil
    ) {
        self.userId = userId
        self.threadId = threadId
        self.messageId = messageId
        self.includeHistory = includeHistory
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

// MARK: - AI Processing State

/// State of AI processing operations
public enum AIProcessingState: Equatable, Sendable {
    case idle
    case processing(operation: String)
    case completed
    case failed(error: String)

    public var isProcessing: Bool {
        if case .processing = self {
            return true
        }
        return false
    }
}
