//
//  SuiteEventTypes.swift
//  EmailApp
//
//  Suite-wide event type constants shared across all Orion iOS apps.
//  These types define the append-only event vocabulary for the Brain scheduler.
//

import Foundation

/// Suite-wide event types for cross-app integration
enum SuiteEventTypes {

    // MARK: - Tasks App Events

    /// Task created in Tasks app
    static let taskCreated = "tasks.task.created"
    /// Task updated (title, description, priority, due date)
    static let taskUpdated = "tasks.task.updated"
    /// Task marked as completed
    static let taskCompleted = "tasks.task.completed"
    /// Task deleted (tombstone - immutable delete marker)
    static let taskDeleted = "tasks.task.tombstone"

    // MARK: - Email App Events

    /// Email thread received/synced
    static let emailThreadReceived = "email.thread.received"
    /// AI extracted a task from email triage
    static let emailTriageTaskExtracted = "email.triage.task_extracted"
    /// Extracted task linked to existing task
    static let emailTriageTaskLinked = "email.triage.task_linked"

    // MARK: - Calendar App Events

    /// User updated their schedule settings (working hours, buffers, etc.)
    static let scheduleSettingsUpdated = "calendar.schedule.settings.updated"
    /// User applied a proposed time block to their calendar
    static let timeblockApplied = "calendar.timeblock.applied"
    /// User overrode/rejected an AI proposal
    static let overrideCreated = "calendar.override.created"
    /// Lock created on an event (prevent AI from moving)
    static let lockCreated = "calendar.lock.created"
    /// Lock removed from an event
    static let lockRemoved = "calendar.lock.removed"
    /// Time block proposal received from Brain
    static let timeblockProposalReceived = "calendar.timeblock.proposal.received"
    /// Time block deleted (tombstone)
    static let timeblockTombstone = "calendar.timeblock.tombstone"

    // MARK: - Scheduler/Brain Derived Events

    /// Brain created a new scheduling proposal
    static let schedulerProposalCreated = "scheduler.proposal.created"
    /// Proposal expired (user didn't act in time)
    static let schedulerProposalExpired = "scheduler.proposal.expired"
    /// Scheduler re-optimized the schedule
    static let schedulerReoptimized = "scheduler.reoptimized"

    // MARK: - Browser App Events

    /// Bookmark created
    static let bookmarkCreated = "browser.bookmark.created"
    /// Reading list item added
    static let readingListAdded = "browser.reading_list.added"
    /// Tab session captured
    static let tabSessionCaptured = "browser.tab_session.captured"
}

// MARK: - Event Type Metadata

extension SuiteEventTypes {

    /// Event types that queue to Brain for processing
    static let brainQueuedTypes: Set<String> = [
        taskCreated,
        taskUpdated,
        taskCompleted,
        emailTriageTaskExtracted,
        scheduleSettingsUpdated,
        timeblockApplied,
        overrideCreated
    ]

    /// Event types that are tombstones (deletions)
    static let tombstoneTypes: Set<String> = [
        taskDeleted,
        timeblockTombstone
    ]

    /// Check if an event type should be queued to Brain
    static func queuesToBrain(_ eventType: String) -> Bool {
        brainQueuedTypes.contains(eventType)
    }

    /// Check if an event type is a tombstone
    static func isTombstone(_ eventType: String) -> Bool {
        tombstoneTypes.contains(eventType)
    }

    /// Get the app domain from an event type
    static func appDomain(for eventType: String) -> String? {
        let components = eventType.split(separator: ".")
        guard let first = components.first else { return nil }
        return String(first)
    }
}
