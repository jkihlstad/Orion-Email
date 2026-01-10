import Foundation

// MARK: - Task Event Payloads

/// Payload for tasks.task.created events
struct TaskCreatedPayload: Codable, Equatable {
    let title: String
    let notes: String?
    let priority: TaskEventPriority
    let dueDate: TimeInterval?
    let parentTaskId: String?

    /// Stable task ID (must remain consistent across edits)
    let stableTaskId: String
}

/// Payload for tasks.task.updated events
struct TaskUpdatedPayload: Codable, Equatable {
    let stableTaskId: String
    let changes: TaskChanges
    let previousVersion: Int
    let newVersion: Int
}

/// Represents changes made to a task
struct TaskChanges: Codable, Equatable {
    var title: String?
    var notes: String?
    var priority: TaskEventPriority?
    var dueDate: TimeInterval?
    var parentTaskId: String?

    var hasChanges: Bool {
        title != nil || notes != nil || priority != nil || dueDate != nil || parentTaskId != nil
    }
}

/// Payload for tasks.task.completed events
struct TaskCompletedPayload: Codable, Equatable {
    let stableTaskId: String
    let completedAt: TimeInterval
    let completedBy: String?
}

/// Payload for tasks.task.tombstone events (deletions)
struct TaskTombstonePayload: Codable, Equatable {
    let stableTaskId: String
    let deletedAt: TimeInterval
    let reason: TaskDeletionReason?
}

enum TaskEventPriority: String, Codable, CaseIterable {
    case low
    case medium
    case high
    case urgent
}

enum TaskDeletionReason: String, Codable {
    case userDeleted = "user_deleted"
    case merged = "merged"
    case duplicate = "duplicate"
    case parentDeleted = "parent_deleted"
}

// MARK: - Email Event Payloads

/// Payload for email.thread.received events
struct EmailThreadReceivedPayload: Codable, Equatable {
    let threadId: String
    let subject: String?
    let snippet: String?
    let participantCount: Int
    let messageCount: Int
    let hasAttachments: Bool
    let labels: [String]
}

/// Payload for email.triage.task_extracted events
struct EmailTriageTaskExtractedPayload: Codable, Equatable {
    let sourceThreadId: String
    let sourceMessageId: String?
    let extractedTask: ExtractedTaskInfo
    let confidence: Double
    let extractionMethod: String
}

/// Information about a task extracted from email
struct ExtractedTaskInfo: Codable, Equatable {
    let title: String
    let notes: String?
    let suggestedPriority: TaskEventPriority?
    let suggestedDueDate: TimeInterval?
}

/// Payload for email.triage.task_linked events
struct EmailTriageTaskLinkedPayload: Codable, Equatable {
    let threadId: String
    let taskId: String
    let linkType: TaskLinkType
    let linkedAt: TimeInterval
}

enum TaskLinkType: String, Codable {
    case extracted = "extracted"
    case manual = "manual"
    case inferred = "inferred"
}

// MARK: - Calendar Event Payloads

/// Payload for calendar.schedule.settings.updated events
struct ScheduleSettingsUpdatedPayload: Codable, Equatable {
    let settingKey: String
    let previousValue: String?
    let newValue: String
    let category: ScheduleSettingCategory
}

enum ScheduleSettingCategory: String, Codable, CaseIterable {
    case workHours = "work_hours"
    case meetingLimits = "meeting_limits"
    case focusBlocks = "focus_blocks"
    case bufferTime = "buffer_time"
    case preferences = "preferences"
}

/// Payload for calendar.timeblock.applied events
struct TimeblockAppliedPayload: Codable, Equatable {
    let eventId: String
    let title: String
    let startAt: TimeInterval
    let endAt: TimeInterval
    let blockType: TimeblockType
    let taskId: String?
    let isRecurring: Bool
}

enum TimeblockType: String, Codable, CaseIterable {
    case focus = "focus"
    case meeting = "meeting"
    case task = "task"
    case buffer = "buffer"
    case personal = "personal"
}

/// Payload for calendar.override.created events
struct OverrideCreatedPayload: Codable, Equatable {
    let overrideId: String
    let eventId: String?
    let startAt: TimeInterval
    let endAt: TimeInterval
    let overrideType: OverrideType
    let reason: String?
}

enum OverrideType: String, Codable {
    case locked = "locked"
    case unlocked = "unlocked"
    case blocked = "blocked"
    case available = "available"
}

// MARK: - Scheduler Event Payloads

/// Payload for scheduler.proposal.created events
struct SchedulerProposalCreatedPayload: Codable, Equatable {
    let proposalId: String
    let proposalType: ProposalType
    let suggestedSlots: [ProposedTimeSlot]
    let taskId: String?
    let expiresAt: TimeInterval
    let confidence: Double
    let reasoning: String?
}

enum ProposalType: String, Codable {
    case reschedule = "reschedule"
    case newBlock = "new_block"
    case optimization = "optimization"
    case conflict = "conflict"
}

/// A proposed time slot from the scheduler
struct ProposedTimeSlot: Codable, Equatable {
    let slotId: String
    let startAt: TimeInterval
    let endAt: TimeInterval
    let score: Double
    let conflicts: [String]?
}

/// Payload for scheduler.proposal.expired events
struct SchedulerProposalExpiredPayload: Codable, Equatable {
    let proposalId: String
    let createdAt: TimeInterval
    let expiredAt: TimeInterval
    let reason: ProposalExpiredReason
}

enum ProposalExpiredReason: String, Codable {
    case timeout = "timeout"
    case superseded = "superseded"
    case conflictResolved = "conflict_resolved"
    case userIgnored = "user_ignored"
}

// MARK: - Payload Parsing Helpers

extension CleanedEvent {

    /// Attempt to decode the payload as a specific type
    func decodePayload<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = try? JSONEncoder().encode(payload),
              let decoded = try? JSONDecoder().decode(type, from: data) else {
            return nil
        }
        return decoded
    }

    /// Decode task created payload
    var taskCreatedPayload: TaskCreatedPayload? {
        guard eventType == SuiteEventTypes.taskCreated else { return nil }
        return decodePayload(TaskCreatedPayload.self)
    }

    /// Decode task updated payload
    var taskUpdatedPayload: TaskUpdatedPayload? {
        guard eventType == SuiteEventTypes.taskUpdated else { return nil }
        return decodePayload(TaskUpdatedPayload.self)
    }

    /// Decode task completed payload
    var taskCompletedPayload: TaskCompletedPayload? {
        guard eventType == SuiteEventTypes.taskCompleted else { return nil }
        return decodePayload(TaskCompletedPayload.self)
    }

    /// Decode task tombstone payload
    var taskTombstonePayload: TaskTombstonePayload? {
        guard eventType == SuiteEventTypes.taskDeleted else { return nil }
        return decodePayload(TaskTombstonePayload.self)
    }

    /// Decode email thread received payload
    var emailThreadReceivedPayload: EmailThreadReceivedPayload? {
        guard eventType == SuiteEventTypes.emailThreadReceived else { return nil }
        return decodePayload(EmailThreadReceivedPayload.self)
    }

    /// Decode scheduler proposal created payload
    var schedulerProposalPayload: SchedulerProposalCreatedPayload? {
        guard eventType == SuiteEventTypes.schedulerProposalCreated else { return nil }
        return decodePayload(SchedulerProposalCreatedPayload.self)
    }
}
