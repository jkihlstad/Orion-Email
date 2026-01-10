import Foundation

// MARK: - Suite-Wide Event Types
/// Shared event type constants used across all Orion suite apps.
/// These types define the contract between apps and the Brain for event synchronization.
enum SuiteEventTypes {

    // MARK: - Tasks
    /// A new task was created
    static let taskCreated = "tasks.task.created"
    /// An existing task was updated (title, notes, priority, etc.)
    static let taskUpdated = "tasks.task.updated"
    /// A task was marked as completed
    static let taskCompleted = "tasks.task.completed"
    /// A task was deleted (tombstone for sync)
    static let taskDeleted = "tasks.task.tombstone"

    // MARK: - Email -> Tasks
    /// A new email thread was received
    static let emailThreadReceived = "email.thread.received"
    /// AI extracted a task from email triage
    static let emailTriageTaskExtracted = "email.triage.task_extracted"
    /// An extracted task was linked to its source email
    static let emailTriageTaskLinked = "email.triage.task_linked"

    // MARK: - Calendar
    /// User updated their scheduling settings (work hours, meeting limits, etc.)
    static let scheduleSettingsUpdated = "calendar.schedule.settings.updated"
    /// A timeblock was applied to the calendar
    static let timeblockApplied = "calendar.timeblock.applied"
    /// User created an override for a specific event or time
    static let overrideCreated = "calendar.override.created"

    // MARK: - Scheduler (Brain -> User)
    /// Brain generated a scheduling proposal for user review
    static let schedulerProposalCreated = "scheduler.proposal.created"
    /// A scheduling proposal expired without user action
    static let schedulerProposalExpired = "scheduler.proposal.expired"
}

// MARK: - Event Type Helpers
extension SuiteEventTypes {

    /// All task-related event types
    static var taskEvents: [String] {
        [taskCreated, taskUpdated, taskCompleted, taskDeleted]
    }

    /// All email-related event types
    static var emailEvents: [String] {
        [emailThreadReceived, emailTriageTaskExtracted, emailTriageTaskLinked]
    }

    /// All calendar-related event types
    static var calendarEvents: [String] {
        [scheduleSettingsUpdated, timeblockApplied, overrideCreated]
    }

    /// All scheduler-related event types
    static var schedulerEvents: [String] {
        [schedulerProposalCreated, schedulerProposalExpired]
    }

    /// Check if an event type represents a deletion/tombstone
    static func isTombstone(_ eventType: String) -> Bool {
        eventType.hasSuffix(".tombstone") || eventType.hasSuffix(".deleted")
    }

    /// Check if an event type is a proposal (requires user action)
    static func isProposal(_ eventType: String) -> Bool {
        eventType.contains(".proposal.")
    }

    /// Extract the domain from an event type (e.g., "tasks" from "tasks.task.created")
    static func domain(for eventType: String) -> String? {
        eventType.split(separator: ".").first.map(String.init)
    }
}
