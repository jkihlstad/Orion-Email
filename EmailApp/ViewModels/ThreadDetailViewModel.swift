import Foundation
import SwiftUI
import Combine

// MARK: - Thread Detail View Model

/// ViewModel for the thread detail view
/// Handles loading thread messages, AI summaries, and applying actions
@MainActor
class ThreadDetailViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var thread: EmailThread?
    @Published var messages: [EmailMessage] = []
    @Published var isLoading = false
    @Published var isLoadingAI = false
    @Published var aiSummary: AIEmailSummary?
    @Published var error: EmailError?

    // MARK: - Private Properties

    private let emailAPI: EmailAPIProtocol
    private let aiAssistant: AIEmailAssistantProtocol
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        emailAPI: EmailAPIProtocol = ConvexEmailAPI(),
        aiAssistant: AIEmailAssistantProtocol = AIEmailAssistant()
    ) {
        self.emailAPI = emailAPI
        self.aiAssistant = aiAssistant
    }

    // MARK: - Public Methods

    /// Loads a thread and its messages
    func loadThread(_ thread: EmailThread) {
        self.thread = thread
        self.messages = thread.messages

        // Mark as read if unread
        if !thread.isRead {
            Task {
                try? await emailAPI.applyAction(threadIds: [thread.id], action: .markRead)
            }
        }

        // Load full messages if needed
        if thread.messages.isEmpty {
            loadFullThread(threadId: thread.id)
        }
    }

    /// Loads the full thread with all messages from API
    func loadFullThread(threadId: String) {
        isLoading = true
        error = nil

        Task {
            do {
                let fullThread = try await emailAPI.getThread(threadId: threadId)
                thread = fullThread
                messages = fullThread.messages.sorted { $0.sentAt < $1.sentAt }
                isLoading = false
            } catch let apiError as EmailError {
                error = apiError
                isLoading = false

                #if DEBUG
                useMockMessages()
                #endif
            } catch {
                self.error = .networkError(error.localizedDescription)
                isLoading = false

                #if DEBUG
                useMockMessages()
                #endif
            }
        }
    }

    /// Loads AI-generated summary and suggestions
    func loadAISummary() async {
        guard let thread = thread else { return }

        isLoadingAI = true

        do {
            let summary = try await aiAssistant.generateSummary(for: thread)
            aiSummary = summary
            isLoadingAI = false
        } catch {
            // AI features are optional, don't show error
            isLoadingAI = false

            #if DEBUG
            aiSummary = .mock
            #endif
        }
    }

    /// Applies an action to the current thread
    func applyAction(_ action: MessageAction) {
        guard let thread = thread else { return }

        // Optimistic update
        optimisticallyUpdate(action: action)

        Task {
            do {
                try await emailAPI.applyAction(threadIds: [thread.id], action: action)
            } catch {
                // Revert on failure
                revertUpdate(action: action)
                Haptics.error()
            }
        }
    }

    /// Applies an action to a specific message
    func applyAction(_ action: MessageAction, to messageId: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }

        // Optimistic update for message
        withAnimation(Theme.Animation.easeFast) {
            switch action {
            case .markRead:
                messages[index].isRead = true
            case .markUnread:
                messages[index].isRead = false
            case .star:
                messages[index].isStarred = true
            case .unstar:
                messages[index].isStarred = false
            default:
                break
            }
        }

        Task {
            do {
                try await emailAPI.applyAction(threadIds: [messageId], action: action)
            } catch {
                Haptics.error()
            }
        }
    }

    /// Asks AI a question about the thread
    func askAI(question: String) async -> String? {
        guard let thread = thread else { return nil }

        do {
            let response = try await aiAssistant.answerQuestion(question, about: thread)
            return response
        } catch {
            return nil
        }
    }

    /// Generates a reply using AI
    func generateReply(tone: SuggestedReply.ReplyTone) async -> String? {
        guard let thread = thread else { return nil }

        do {
            let reply = try await aiAssistant.generateReply(for: thread, tone: tone)
            return reply
        } catch {
            return nil
        }
    }

    // MARK: - Private Methods

    private func optimisticallyUpdate(action: MessageAction) {
        guard thread != nil else { return }

        withAnimation(Theme.Animation.easeFast) {
            switch action {
            case .markRead:
                thread?.isRead = true
            case .markUnread:
                thread?.isRead = false
            case .star:
                thread?.isStarred = true
            case .unstar:
                thread?.isStarred = false
            case .archive:
                thread?.isArchived = true
            case .trash:
                thread?.isTrashed = true
            case .spam:
                thread?.isSpam = true
            default:
                break
            }
        }
    }

    private func revertUpdate(action: MessageAction) {
        guard thread != nil else { return }

        withAnimation(Theme.Animation.easeFast) {
            switch action {
            case .markRead:
                thread?.isRead = false
            case .markUnread:
                thread?.isRead = true
            case .star:
                thread?.isStarred = false
            case .unstar:
                thread?.isStarred = true
            case .archive:
                thread?.isArchived = false
            case .trash:
                thread?.isTrashed = false
            case .spam:
                thread?.isSpam = false
            default:
                break
            }
        }
    }

    private func useMockMessages() {
        messages = [.mock]
    }
}

// MARK: - AI Email Assistant Protocol

/// Protocol for AI-powered email features
protocol AIEmailAssistantProtocol {
    func generateSummary(for thread: EmailThread) async throws -> AIEmailSummary
    func generateReply(for thread: EmailThread, tone: SuggestedReply.ReplyTone) async throws -> String
    func answerQuestion(_ question: String, about thread: EmailThread) async throws -> String
}

// MARK: - AI Email Assistant Implementation

/// Implementation of AI email assistant
/// In production, this would call an AI service
class AIEmailAssistant: AIEmailAssistantProtocol {
    func generateSummary(for thread: EmailThread) async throws -> AIEmailSummary {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // In production, this would call an AI API
        // For now, return a generated summary based on the thread

        let keyPoints = extractKeyPoints(from: thread)
        let actionItems = extractActionItems(from: thread)
        let sentiment = analyzeSentiment(for: thread)
        let suggestedReplies = generateSuggestedReplies(for: thread)

        return AIEmailSummary(
            threadId: thread.id,
            summary: generateSummaryText(for: thread),
            keyPoints: keyPoints,
            suggestedReplies: suggestedReplies,
            sentiment: sentiment,
            actionItems: actionItems,
            generatedAt: Date()
        )
    }

    func generateReply(for thread: EmailThread, tone: SuggestedReply.ReplyTone) async throws -> String {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 500_000_000)

        // In production, this would call an AI API
        switch tone {
        case .professional:
            return "Thank you for your email. I have reviewed the information and will get back to you with a detailed response shortly."
        case .casual:
            return "Thanks for reaching out! I'll take a look and get back to you soon."
        case .brief:
            return "Got it, thanks!"
        case .detailed:
            return "Thank you for sharing this information. I've carefully reviewed the details and have a few thoughts to share.\n\nFirst, regarding the main points you mentioned, I believe we should...\n\nPlease let me know if you have any questions or need any clarification."
        }
    }

    func answerQuestion(_ question: String, about thread: EmailThread) async throws -> String {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 750_000_000)

        // In production, this would call an AI API with the question and thread context
        return "Based on the email thread, here's what I found relevant to your question:\n\n\(thread.snippet)\n\nWould you like me to elaborate on any specific aspect?"
    }

    // MARK: - Private Helpers

    private func extractKeyPoints(from thread: EmailThread) -> [String] {
        // Simple extraction based on thread content
        var points: [String] = []

        if thread.hasAttachments {
            points.append("Contains attachments that may require review")
        }

        if thread.messagesCount > 3 {
            points.append("This is an ongoing conversation with \(thread.messagesCount) messages")
        }

        if !thread.isRead {
            points.append("This thread has unread messages")
        }

        if points.isEmpty {
            points.append("General inquiry or update")
        }

        return points
    }

    private func extractActionItems(from thread: EmailThread) -> [String] {
        // Simple action item detection
        var items: [String] = []

        let lowercaseSnippet = thread.snippet.lowercased()

        if lowercaseSnippet.contains("please") || lowercaseSnippet.contains("could you") {
            items.append("Review and respond to the request")
        }

        if lowercaseSnippet.contains("meeting") || lowercaseSnippet.contains("call") {
            items.append("Check calendar for availability")
        }

        if lowercaseSnippet.contains("deadline") || lowercaseSnippet.contains("by") {
            items.append("Note any mentioned deadlines")
        }

        if thread.hasAttachments {
            items.append("Review attached documents")
        }

        return items
    }

    private func analyzeSentiment(for thread: EmailThread) -> AIEmailSummary.Sentiment {
        let lowercaseSnippet = thread.snippet.lowercased()

        if lowercaseSnippet.contains("urgent") || lowercaseSnippet.contains("asap") || lowercaseSnippet.contains("immediately") {
            return .urgent
        }

        if lowercaseSnippet.contains("great") || lowercaseSnippet.contains("thank") || lowercaseSnippet.contains("excellent") {
            return .positive
        }

        if lowercaseSnippet.contains("concern") || lowercaseSnippet.contains("issue") || lowercaseSnippet.contains("problem") {
            return .negative
        }

        return .neutral
    }

    private func generateSuggestedReplies(for thread: EmailThread) -> [SuggestedReply] {
        return [
            SuggestedReply(
                id: "reply-1",
                label: "Acknowledge",
                content: "Thank you for your email. I'll review this and get back to you shortly.",
                tone: .professional
            ),
            SuggestedReply(
                id: "reply-2",
                label: "Quick Reply",
                content: "Thanks! Got it.",
                tone: .brief
            ),
            SuggestedReply(
                id: "reply-3",
                label: "Follow Up",
                content: "Thanks for the update. Could you provide more details on...",
                tone: .detailed
            )
        ]
    }

    private func generateSummaryText(for thread: EmailThread) -> String {
        let sender = thread.primarySender?.displayName ?? "Someone"
        let subject = thread.subject.isEmpty ? "an email" : "about \"\(thread.subject)\""

        return "\(sender) sent \(subject). The email discusses \(thread.snippet.prefix(100))..."
    }
}
