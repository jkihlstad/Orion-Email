import Foundation
import SwiftUI

// MARK: - Email Account

/// Represents an email account (e.g., Gmail, Outlook)
struct EmailAccount: Identifiable, Codable, Hashable {
    let id: String
    let email: String
    let displayName: String
    let avatarURL: URL?
    let provider: EmailProvider
    let isActive: Bool
    let lastSyncedAt: Date?

    enum EmailProvider: String, Codable, Hashable {
        case gmail
        case outlook
        case icloud
        case other

        var displayName: String {
            switch self {
            case .gmail: return "Gmail"
            case .outlook: return "Outlook"
            case .icloud: return "iCloud"
            case .other: return "Email"
            }
        }

        var iconName: String {
            switch self {
            case .gmail: return "envelope.fill"
            case .outlook: return "envelope.badge.fill"
            case .icloud: return "icloud.fill"
            case .other: return "envelope"
            }
        }
    }
}

// MARK: - Email Label

/// Represents an email label/folder
struct EmailLabel: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let type: LabelType
    let color: String?
    var unreadCount: Int
    var totalCount: Int
    let isHidden: Bool

    var displayColor: Color {
        guard let colorHex = color else {
            return type.defaultColor
        }
        return Color(hex: colorHex) ?? type.defaultColor
    }

    var iconName: String {
        type.iconName
    }
}

enum LabelType: String, Codable, Hashable {
    case inbox
    case sent
    case drafts
    case spam
    case trash
    case starred
    case important
    case all
    case custom

    var displayName: String {
        switch self {
        case .inbox: return "Inbox"
        case .sent: return "Sent"
        case .drafts: return "Drafts"
        case .spam: return "Spam"
        case .trash: return "Trash"
        case .starred: return "Starred"
        case .important: return "Important"
        case .all: return "All Mail"
        case .custom: return "Label"
        }
    }

    var iconName: String {
        switch self {
        case .inbox: return "tray.fill"
        case .sent: return "paperplane.fill"
        case .drafts: return "doc.text.fill"
        case .spam: return "exclamationmark.shield.fill"
        case .trash: return "trash.fill"
        case .starred: return "star.fill"
        case .important: return "bookmark.fill"
        case .all: return "tray.2.fill"
        case .custom: return "tag.fill"
        }
    }

    var defaultColor: Color {
        switch self {
        case .inbox: return .blue
        case .sent: return .green
        case .drafts: return .orange
        case .spam: return .red
        case .trash: return .gray
        case .starred: return .yellow
        case .important: return .orange
        case .all: return .purple
        case .custom: return .blue
        }
    }
}

// MARK: - Email Participant

/// Represents an email sender or recipient
struct EmailParticipant: Identifiable, Codable, Hashable {
    let id: String
    let email: String
    let name: String?
    let avatarURL: URL?

    var displayName: String {
        name ?? email.components(separatedBy: "@").first ?? email
    }

    var initials: String {
        let components = displayName.components(separatedBy: " ")
        if components.count >= 2 {
            let first = components.first?.first ?? Character(" ")
            let last = components.last?.first ?? Character(" ")
            return "\(first)\(last)".uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }
}

// MARK: - Email Attachment

/// Represents an email attachment
struct EmailAttachment: Identifiable, Codable, Hashable {
    let id: String
    let filename: String
    let mimeType: String
    let size: Int64
    let downloadURL: URL?
    let thumbnailURL: URL?

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var iconName: String {
        if mimeType.starts(with: "image/") {
            return "photo.fill"
        } else if mimeType.starts(with: "video/") {
            return "video.fill"
        } else if mimeType.starts(with: "audio/") {
            return "waveform"
        } else if mimeType.contains("pdf") {
            return "doc.richtext.fill"
        } else if mimeType.contains("word") || mimeType.contains("document") {
            return "doc.fill"
        } else if mimeType.contains("spreadsheet") || mimeType.contains("excel") {
            return "tablecells.fill"
        } else if mimeType.contains("presentation") || mimeType.contains("powerpoint") {
            return "play.rectangle.fill"
        } else if mimeType.contains("zip") || mimeType.contains("archive") {
            return "doc.zipper"
        }
        return "paperclip"
    }

    var isImage: Bool {
        mimeType.starts(with: "image/")
    }
}

// MARK: - Email Message

/// Represents a single email message within a thread
struct EmailMessage: Identifiable, Codable, Hashable {
    let id: String
    let threadId: String
    let sender: EmailParticipant
    let recipients: [EmailParticipant]
    let ccRecipients: [EmailParticipant]
    let bccRecipients: [EmailParticipant]
    let subject: String
    let snippet: String
    let bodyPlainText: String
    let bodyHTML: String?
    let attachments: [EmailAttachment]
    let sentAt: Date
    let receivedAt: Date
    var isRead: Bool
    var isStarred: Bool
    let headers: [String: String]?

    var hasAttachments: Bool {
        !attachments.isEmpty
    }

    var allRecipients: [EmailParticipant] {
        recipients + ccRecipients + bccRecipients
    }
}

// MARK: - Email Thread

/// Represents an email thread (conversation)
struct EmailThread: Identifiable, Codable, Hashable {
    let id: String
    let accountId: String
    let subject: String
    let snippet: String
    let participants: [EmailParticipant]
    var messages: [EmailMessage]
    var labels: [EmailLabel]
    var isRead: Bool
    var isStarred: Bool
    var isArchived: Bool
    var isTrashed: Bool
    var isSpam: Bool
    let hasAttachments: Bool
    let lastMessageAt: Date
    let messagesCount: Int

    var latestMessage: EmailMessage? {
        messages.max(by: { $0.sentAt < $1.sentAt })
    }

    var primarySender: EmailParticipant? {
        latestMessage?.sender ?? participants.first
    }

    var unreadCount: Int {
        messages.filter { !$0.isRead }.count
    }

    var formattedDate: String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(lastMessageAt) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: lastMessageAt)
        } else if calendar.isDateInYesterday(lastMessageAt) {
            return "Yesterday"
        } else if let daysAgo = calendar.dateComponents([.day], from: lastMessageAt, to: now).day, daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: lastMessageAt)
        } else if calendar.component(.year, from: lastMessageAt) == calendar.component(.year, from: now) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: lastMessageAt)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM/dd/yy"
            return formatter.string(from: lastMessageAt)
        }
    }
}

// MARK: - Message Action

/// Actions that can be performed on emails
enum MessageAction: String, Codable, Hashable {
    case markRead
    case markUnread
    case star
    case unstar
    case archive
    case unarchive
    case trash
    case restore
    case spam
    case notSpam
    case delete
    case addLabel
    case removeLabel
    case move
}

// MARK: - AI Summary

/// AI-generated summary and insights for an email thread
struct AIEmailSummary: Codable, Hashable {
    let threadId: String
    let summary: String
    let keyPoints: [String]
    let suggestedReplies: [SuggestedReply]
    let sentiment: Sentiment?
    let actionItems: [String]
    let generatedAt: Date

    enum Sentiment: String, Codable, Hashable {
        case positive
        case neutral
        case negative
        case urgent

        var color: Color {
            switch self {
            case .positive: return .green
            case .neutral: return .blue
            case .negative: return .orange
            case .urgent: return .red
            }
        }

        var iconName: String {
            switch self {
            case .positive: return "face.smiling"
            case .neutral: return "face.dashed"
            case .negative: return "exclamationmark.circle"
            case .urgent: return "exclamationmark.triangle"
            }
        }
    }
}

/// A suggested reply generated by AI
struct SuggestedReply: Identifiable, Codable, Hashable {
    let id: String
    let label: String
    let content: String
    let tone: ReplyTone

    enum ReplyTone: String, Codable, Hashable {
        case professional
        case casual
        case brief
        case detailed

        var iconName: String {
            switch self {
            case .professional: return "briefcase.fill"
            case .casual: return "hand.wave.fill"
            case .brief: return "text.alignleft"
            case .detailed: return "doc.text.fill"
            }
        }
    }
}

// MARK: - Draft

/// Represents an email draft
struct EmailDraft: Identifiable, Codable, Hashable {
    let id: String
    let accountId: String
    var replyToMessageId: String?
    var replyToThreadId: String?
    var recipients: [EmailParticipant]
    var ccRecipients: [EmailParticipant]
    var bccRecipients: [EmailParticipant]
    var subject: String
    var body: String
    var attachments: [EmailAttachment]
    let createdAt: Date
    var updatedAt: Date
    var isDraft: Bool
}

// MARK: - Search

/// Search filters for emails
struct EmailSearchFilters: Codable, Hashable {
    var query: String?
    var from: String?
    var to: String?
    var subject: String?
    var hasAttachment: Bool?
    var isUnread: Bool?
    var isStarred: Bool?
    var labelIds: [String]?
    var after: Date?
    var before: Date?

    var isEmpty: Bool {
        query == nil &&
        from == nil &&
        to == nil &&
        subject == nil &&
        hasAttachment == nil &&
        isUnread == nil &&
        isStarred == nil &&
        (labelIds?.isEmpty ?? true) &&
        after == nil &&
        before == nil
    }

    var activeFiltersCount: Int {
        var count = 0
        if from != nil { count += 1 }
        if to != nil { count += 1 }
        if subject != nil { count += 1 }
        if hasAttachment != nil { count += 1 }
        if isUnread != nil { count += 1 }
        if isStarred != nil { count += 1 }
        if !(labelIds?.isEmpty ?? true) { count += 1 }
        if after != nil { count += 1 }
        if before != nil { count += 1 }
        return count
    }
}

/// Recent search entry
struct RecentSearch: Identifiable, Codable, Hashable {
    let id: String
    let query: String
    let searchedAt: Date
}

// MARK: - Consent Types

/// Types of user consent for data processing
enum ConsentType: String, Codable, Hashable, CaseIterable {
    case emailContent = "email.content"
    case audioCapture = "audio.capture"
    case aiAnalysis = "ai.analysis"
    case syncContacts = "sync.contacts"
    case usageAnalytics = "usage.analytics"

    var displayName: String {
        switch self {
        case .emailContent: return "Email Content Access"
        case .audioCapture: return "Voice & Audio Capture"
        case .aiAnalysis: return "AI Analysis & Suggestions"
        case .syncContacts: return "Contact Sync"
        case .usageAnalytics: return "Usage Analytics"
        }
    }

    var description: String {
        switch self {
        case .emailContent:
            return "Allow the app to read and process your email content to provide features like search, organization, and AI summaries."
        case .audioCapture:
            return "Enable voice dictation for composing emails and voice commands for hands-free operation."
        case .aiAnalysis:
            return "Use AI to analyze emails, generate summaries, suggest replies, and identify action items."
        case .syncContacts:
            return "Sync your contacts to improve recipient suggestions and email organization."
        case .usageAnalytics:
            return "Collect anonymous usage data to help improve the app experience."
        }
    }

    var iconName: String {
        switch self {
        case .emailContent: return "envelope.open.fill"
        case .audioCapture: return "mic.fill"
        case .aiAnalysis: return "brain.head.profile"
        case .syncContacts: return "person.2.fill"
        case .usageAnalytics: return "chart.bar.fill"
        }
    }

    var isRequired: Bool {
        switch self {
        case .emailContent: return true
        default: return false
        }
    }
}

/// User consent record
struct UserConsent: Identifiable, Codable, Hashable {
    let id: String
    let type: ConsentType
    var isGranted: Bool
    let grantedAt: Date?
    let revokedAt: Date?
}

// MARK: - App State

/// Authentication state for the app
enum AuthState: Equatable {
    case unknown
    case unauthenticated
    case authenticating
    case authenticated(EmailAccount)
    case error(String)

    static func == (lhs: AuthState, rhs: AuthState) -> Bool {
        switch (lhs, rhs) {
        case (.unknown, .unknown): return true
        case (.unauthenticated, .unauthenticated): return true
        case (.authenticating, .authenticating): return true
        case (.authenticated(let a1), .authenticated(let a2)): return a1.id == a2.id
        case (.error(let e1), .error(let e2)): return e1 == e2
        default: return false
        }
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }

        let length = hexSanitized.count

        if length == 6 {
            let r = Double((rgb >> 16) & 0xFF) / 255.0
            let g = Double((rgb >> 8) & 0xFF) / 255.0
            let b = Double(rgb & 0xFF) / 255.0
            self.init(red: r, green: g, blue: b)
        } else if length == 8 {
            let r = Double((rgb >> 24) & 0xFF) / 255.0
            let g = Double((rgb >> 16) & 0xFF) / 255.0
            let b = Double((rgb >> 8) & 0xFF) / 255.0
            let a = Double(rgb & 0xFF) / 255.0
            self.init(red: r, green: g, blue: b, opacity: a)
        } else {
            return nil
        }
    }
}

// MARK: - Mock Data

extension EmailAccount {
    static let mock = EmailAccount(
        id: "account-1",
        email: "user@gmail.com",
        displayName: "John Doe",
        avatarURL: nil,
        provider: .gmail,
        isActive: true,
        lastSyncedAt: Date()
    )
}

extension EmailLabel {
    static let inbox = EmailLabel(id: "INBOX", name: "Inbox", type: .inbox, color: nil, unreadCount: 5, totalCount: 120, isHidden: false)
    static let sent = EmailLabel(id: "SENT", name: "Sent", type: .sent, color: nil, unreadCount: 0, totalCount: 45, isHidden: false)
    static let drafts = EmailLabel(id: "DRAFTS", name: "Drafts", type: .drafts, color: nil, unreadCount: 0, totalCount: 3, isHidden: false)
    static let spam = EmailLabel(id: "SPAM", name: "Spam", type: .spam, color: nil, unreadCount: 2, totalCount: 12, isHidden: false)
    static let trash = EmailLabel(id: "TRASH", name: "Trash", type: .trash, color: nil, unreadCount: 0, totalCount: 8, isHidden: false)
    static let starred = EmailLabel(id: "STARRED", name: "Starred", type: .starred, color: nil, unreadCount: 0, totalCount: 15, isHidden: false)

    static let allSystemLabels: [EmailLabel] = [.inbox, .starred, .sent, .drafts, .spam, .trash]
}

extension EmailParticipant {
    static let mockSender = EmailParticipant(
        id: "participant-1",
        email: "alice@example.com",
        name: "Alice Johnson",
        avatarURL: nil
    )

    static let mockRecipient = EmailParticipant(
        id: "participant-2",
        email: "user@gmail.com",
        name: "John Doe",
        avatarURL: nil
    )
}

extension EmailMessage {
    static let mock = EmailMessage(
        id: "msg-1",
        threadId: "thread-1",
        sender: .mockSender,
        recipients: [.mockRecipient],
        ccRecipients: [],
        bccRecipients: [],
        subject: "Project Update - Q4 Planning",
        snippet: "Hi John, I wanted to share the latest updates on our Q4 planning...",
        bodyPlainText: "Hi John,\n\nI wanted to share the latest updates on our Q4 planning. We've made significant progress on the roadmap and I'd love to get your feedback.\n\nBest,\nAlice",
        bodyHTML: nil,
        attachments: [],
        sentAt: Date().addingTimeInterval(-3600),
        receivedAt: Date().addingTimeInterval(-3500),
        isRead: false,
        isStarred: false,
        headers: nil
    )
}

extension EmailThread {
    static let mock = EmailThread(
        id: "thread-1",
        accountId: "account-1",
        subject: "Project Update - Q4 Planning",
        snippet: "Hi John, I wanted to share the latest updates on our Q4 planning...",
        participants: [.mockSender, .mockRecipient],
        messages: [.mock],
        labels: [.inbox],
        isRead: false,
        isStarred: false,
        isArchived: false,
        isTrashed: false,
        isSpam: false,
        hasAttachments: false,
        lastMessageAt: Date().addingTimeInterval(-3600),
        messagesCount: 1
    )

    static let mockThreads: [EmailThread] = [
        .mock,
        EmailThread(
            id: "thread-2",
            accountId: "account-1",
            subject: "Meeting Tomorrow",
            snippet: "Don't forget about our meeting tomorrow at 10am...",
            participants: [
                EmailParticipant(id: "p-3", email: "bob@example.com", name: "Bob Smith", avatarURL: nil),
                .mockRecipient
            ],
            messages: [],
            labels: [.inbox],
            isRead: true,
            isStarred: true,
            isArchived: false,
            isTrashed: false,
            isSpam: false,
            hasAttachments: true,
            lastMessageAt: Date().addingTimeInterval(-7200),
            messagesCount: 3
        ),
        EmailThread(
            id: "thread-3",
            accountId: "account-1",
            subject: "Invoice #1234",
            snippet: "Please find attached the invoice for services rendered...",
            participants: [
                EmailParticipant(id: "p-4", email: "billing@company.com", name: "Billing Department", avatarURL: nil),
                .mockRecipient
            ],
            messages: [],
            labels: [.inbox],
            isRead: true,
            isStarred: false,
            isArchived: false,
            isTrashed: false,
            isSpam: false,
            hasAttachments: true,
            lastMessageAt: Date().addingTimeInterval(-86400),
            messagesCount: 1
        )
    ]
}

extension AIEmailSummary {
    static let mock = AIEmailSummary(
        threadId: "thread-1",
        summary: "Alice is providing an update on Q4 planning and requesting feedback on the roadmap progress.",
        keyPoints: [
            "Q4 planning is underway",
            "Significant progress on roadmap",
            "Feedback is requested"
        ],
        suggestedReplies: [
            SuggestedReply(id: "reply-1", label: "Acknowledge", content: "Thanks for the update, Alice! I'll review the roadmap and get back to you with my thoughts.", tone: .professional),
            SuggestedReply(id: "reply-2", label: "Request Meeting", content: "Great progress! Let's schedule a call to discuss the details.", tone: .brief),
            SuggestedReply(id: "reply-3", label: "Ask Questions", content: "Thanks for sharing! I have a few questions about the timeline and resource allocation.", tone: .detailed)
        ],
        sentiment: .positive,
        actionItems: ["Review roadmap", "Provide feedback to Alice"],
        generatedAt: Date()
    )
}
