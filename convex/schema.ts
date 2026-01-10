/**
 * Convex Schema for the Orion Email App
 *
 * Privacy/Consent Model:
 * - All tables are partitioned by userId (enforced at query/mutation level)
 * - No cross-user data access is permitted
 * - Access tokens are stored as encrypted references, not plain text
 * - Tombstones track all deletions for compliance and sync
 * - Events table supports append-only pattern - no updates, corrections are new events
 *
 * Index Strategy:
 * - Primary queries are by userId + accountId combination
 * - Secondary indexes support filtering by labels, dates, and search
 * - All indexes are designed for efficient cursor-based pagination
 */

import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  // ============================================================================
  // Email Accounts
  // ============================================================================
  /**
   * User's connected email accounts (Gmail, Outlook, IMAP)
   * One user can have multiple accounts
   */
  emailAccounts: defineTable({
    userId: v.string(),
    provider: v.union(v.literal("gmail"), v.literal("imap"), v.literal("outlook")),
    emailAddress: v.string(),
    /** Encrypted reference to access token - NOT the token itself */
    accessTokenRef: v.optional(v.string()),
    /** Encrypted reference to refresh token - NOT the token itself */
    refreshTokenRef: v.optional(v.string()),
    status: v.union(v.literal("active"), v.literal("disconnected"), v.literal("error")),
    /** Error message if status is "error" */
    errorMessage: v.optional(v.string()),
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    // Primary query: get all accounts for a user
    .index("by_user", ["userId"])
    // Lookup by email address (for deduplication)
    .index("by_user_email", ["userId", "emailAddress"])
    // Find accounts by status (for monitoring/retry logic)
    .index("by_status", ["status"]),

  // ============================================================================
  // Email Threads (Conversations)
  // ============================================================================
  /**
   * Email threads aggregate messages into conversations
   * Threads are provider-specific (Gmail threads, Outlook conversations)
   */
  emailThreads: defineTable({
    userId: v.string(),
    accountId: v.id("emailAccounts"),
    /** Provider-specific thread ID (e.g., Gmail thread ID) */
    threadId: v.string(),
    /** Short preview of latest message */
    snippet: v.string(),
    /** Subject line */
    subject: v.string(),
    /** Timestamp of most recent message (for sorting) */
    lastMessageAt: v.number(),
    /** Count of unread messages in thread */
    unreadCount: v.number(),
    /** Label IDs applied to this thread */
    labels: v.array(v.string()),
    /** All participants in the thread */
    participants: v.array(
      v.object({
        email: v.string(),
        name: v.optional(v.string()),
      })
    ),
    /** Whether any message has attachments */
    hasAttachments: v.boolean(),
    /** Starred status */
    isStarred: v.boolean(),
    /** Last update timestamp (for sync) */
    updatedAt: v.number(),
  })
    // Primary query: threads by account, sorted by date (inbox view)
    .index("by_account_date", ["userId", "accountId", "lastMessageAt"])
    // Lookup specific thread by provider ID
    .index("by_account_threadId", ["userId", "accountId", "threadId"])
    // Filter by starred
    .index("by_account_starred", ["userId", "accountId", "isStarred", "lastMessageAt"])
    // For sync: find recently updated threads
    .index("by_account_updated", ["userId", "accountId", "updatedAt"]),

  // ============================================================================
  // Email Messages
  // ============================================================================
  /**
   * Individual email messages within threads
   * Body content stored separately (bodyRef, htmlBodyRef) for efficiency
   */
  emailMessages: defineTable({
    userId: v.string(),
    accountId: v.id("emailAccounts"),
    /** Provider-specific message ID */
    messageId: v.string(),
    /** Thread this message belongs to */
    threadId: v.string(),
    /** Sender */
    from: v.object({
      email: v.string(),
      name: v.optional(v.string()),
    }),
    /** Recipients */
    to: v.array(
      v.object({
        email: v.string(),
        name: v.optional(v.string()),
      })
    ),
    /** CC recipients */
    cc: v.array(
      v.object({
        email: v.string(),
        name: v.optional(v.string()),
      })
    ),
    /** BCC recipients (only visible for sent mail) */
    bcc: v.array(
      v.object({
        email: v.string(),
        name: v.optional(v.string()),
      })
    ),
    /** Subject line */
    subject: v.string(),
    /** Short preview text */
    snippet: v.string(),
    /** Storage reference for plain text body */
    bodyRef: v.optional(v.string()),
    /** Storage reference for HTML body */
    htmlBodyRef: v.optional(v.string()),
    /** Provider's internal date (for sorting) */
    internalDate: v.number(),
    /** Attachment metadata */
    attachments: v.array(
      v.object({
        id: v.string(),
        filename: v.string(),
        mimeType: v.string(),
        size: v.number(),
        contentRef: v.optional(v.string()),
        contentId: v.optional(v.string()),
        isInline: v.boolean(),
      })
    ),
    /** Provider label IDs */
    labelIds: v.array(v.string()),
    /** Selected email headers */
    headers: v.optional(v.any()),
    /** Read status */
    isRead: v.boolean(),
    /** Starred status */
    isStarred: v.boolean(),
  })
    // Lookup by provider message ID (for deduplication during sync)
    .index("by_account_messageId", ["userId", "accountId", "messageId"])
    // Get all messages in a thread, sorted by date
    .index("by_thread", ["userId", "accountId", "threadId", "internalDate"])
    // Find messages by date (for cleanup/archival)
    .index("by_account_date", ["userId", "accountId", "internalDate"]),

  // ============================================================================
  // Email Labels (Folders/Tags)
  // ============================================================================
  /**
   * Labels are folders in IMAP, labels in Gmail, folders in Outlook
   * System labels are provider-managed (INBOX, SENT, TRASH, etc.)
   * User labels are custom tags/folders
   */
  emailLabels: defineTable({
    userId: v.string(),
    accountId: v.id("emailAccounts"),
    /** Provider-specific label ID */
    labelId: v.string(),
    /** Display name */
    name: v.string(),
    /** System (INBOX, SENT) or user-created */
    type: v.union(v.literal("system"), v.literal("user")),
    /** Optional color for UI display */
    color: v.optional(v.string()),
    /** Total messages with this label */
    messageCount: v.number(),
    /** Unread messages with this label */
    unreadCount: v.number(),
  })
    // Get all labels for an account
    .index("by_account", ["userId", "accountId"])
    // Lookup specific label by provider ID
    .index("by_account_labelId", ["userId", "accountId", "labelId"]),

  // ============================================================================
  // Email Sync State
  // ============================================================================
  /**
   * Tracks sync progress for incremental sync
   * historyId for Gmail, UIDVALIDITY/HIGHESTMODSEQ for IMAP
   */
  emailSyncState: defineTable({
    userId: v.string(),
    accountId: v.id("emailAccounts"),
    /** Gmail historyId or provider-specific cursor */
    historyId: v.optional(v.string()),
    /** Pagination cursor for full sync */
    cursor: v.optional(v.string()),
    /** Last successful sync timestamp */
    lastSyncAt: v.number(),
    /** Current sync status */
    syncStatus: v.union(v.literal("idle"), v.literal("syncing"), v.literal("error")),
    /** Error message if status is error */
    errorMessage: v.optional(v.string()),
  })
    // Get sync state for an account
    .index("by_account", ["userId", "accountId"])
    // Find accounts that need sync (by status)
    .index("by_status", ["syncStatus", "lastSyncAt"]),

  // ============================================================================
  // Email Drafts
  // ============================================================================
  /**
   * User's draft emails, may or may not be synced to provider
   */
  emailDrafts: defineTable({
    userId: v.string(),
    accountId: v.id("emailAccounts"),
    /** Provider draft ID if synced */
    draftId: v.optional(v.string()),
    /** Recipients */
    to: v.array(
      v.object({
        email: v.string(),
        name: v.optional(v.string()),
      })
    ),
    /** CC recipients */
    cc: v.array(
      v.object({
        email: v.string(),
        name: v.optional(v.string()),
      })
    ),
    /** BCC recipients */
    bcc: v.array(
      v.object({
        email: v.string(),
        name: v.optional(v.string()),
      })
    ),
    /** Subject */
    subject: v.string(),
    /** Plain text body */
    body: v.string(),
    /** HTML body if rich text */
    htmlBody: v.optional(v.string()),
    /** Attachments to send */
    attachments: v.array(
      v.object({
        id: v.string(),
        filename: v.string(),
        mimeType: v.string(),
        size: v.number(),
        contentRef: v.optional(v.string()),
        contentId: v.optional(v.string()),
        isInline: v.boolean(),
      })
    ),
    /** Reply to message ID */
    replyToMessageId: v.optional(v.string()),
    /** Forward from message ID */
    forwardFromMessageId: v.optional(v.string()),
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    // Get all drafts for an account
    .index("by_account", ["userId", "accountId", "updatedAt"])
    // Lookup by provider draft ID
    .index("by_account_draftId", ["userId", "accountId", "draftId"]),

  // ============================================================================
  // Email Tombstones
  // ============================================================================
  /**
   * Tracks deletions for sync and compliance
   * When entities are deleted, a tombstone is created
   * This supports incremental sync and audit requirements
   */
  emailTombstones: defineTable({
    userId: v.string(),
    entityType: v.union(
      v.literal("thread"),
      v.literal("message"),
      v.literal("label"),
      v.literal("draft"),
      v.literal("account")
    ),
    /** Original entity ID (could be Convex ID or provider ID) */
    entityId: v.string(),
    /** When deletion occurred */
    deletedAt: v.number(),
  })
    // Query tombstones by type and date (for sync)
    .index("by_user_type", ["userId", "entityType", "deletedAt"])
    // Cleanup old tombstones
    .index("by_deleted", ["deletedAt"]),

  // ============================================================================
  // Events (Append-Only Event Store)
  // ============================================================================
  /**
   * Append-only event store for all email activity
   * Events are immutable - corrections are new events
   * brainStatus tracks AI processing status
   *
   * Event Types:
   * - email.message.received: New message arrived
   * - email.message.sent: Message was sent
   * - email.thread.updated: Thread metadata changed
   * - email.action.applied: User action (archive, trash, etc.)
   * - email.draft.created/updated/deleted: Draft lifecycle
   * - email.label.created/deleted: Label management
   * - email.account.connected/disconnected: Account lifecycle
   * - email.sync.completed: Sync operation finished
   */
  events: defineTable({
    userId: v.string(),
    /** Event type (namespaced) */
    type: v.string(),
    /** Event payload (type-specific) */
    payload: v.any(),
    /** When the event occurred */
    timestamp: v.number(),
    /** Brain AI processing status */
    brainStatus: v.union(
      v.literal("pending"),
      v.literal("processing"),
      v.literal("processed"),
      v.literal("failed"),
      v.literal("skipped")
    ),
    /** Idempotency key for deduplication */
    idempotencyKey: v.optional(v.string()),
    /** Error message if brainStatus is "failed" */
    brainError: v.optional(v.string()),
    /** When brain processing completed */
    brainProcessedAt: v.optional(v.number()),
  })
    // Query events by user and type
    .index("by_user_type", ["userId", "type", "timestamp"])
    // Query events pending brain processing
    .index("by_brain_status", ["brainStatus", "timestamp"])
    // Idempotency lookup
    .index("by_idempotency", ["userId", "idempotencyKey"])
    // All events by user (for full history)
    .index("by_user", ["userId", "timestamp"]),

  // ============================================================================
  // Idempotency Keys
  // ============================================================================
  /**
   * Track processed idempotency keys to prevent duplicate operations
   * Keys expire after 24 hours
   */
  idempotencyKeys: defineTable({
    key: v.string(),
    userId: v.string(),
    /** Result of the operation (for returning on duplicate requests) */
    result: v.optional(v.any()),
    /** When the key was created */
    createdAt: v.number(),
    /** When the key expires */
    expiresAt: v.number(),
  })
    // Primary lookup
    .index("by_key", ["userId", "key"])
    // Cleanup expired keys
    .index("by_expires", ["expiresAt"]),

  // ============================================================================
  // Calendar System - Users
  // ============================================================================
  /**
   * Calendar users (may differ from email users in consent/preferences)
   */
  users: defineTable({
    clerkUserId: v.string(),
    email: v.string(),
    role: v.union(v.literal("user"), v.literal("admin")),
    createdAt: v.number(),
  })
    .index("by_clerk_id", ["clerkUserId"])
    .index("by_email", ["email"]),

  // ============================================================================
  // Calendar System - User Consents
  // ============================================================================
  /**
   * Tracks user consent for various calendar operations
   */
  userConsents: defineTable({
    clerkUserId: v.string(),
    version: v.string(),
    scopes: v.array(v.string()),
    updatedAt: v.number(),
  })
    .index("by_clerk_id", ["clerkUserId"]),

  // ============================================================================
  // Calendar System - Calendar Accounts
  // ============================================================================
  /**
   * Connected calendar accounts (Google Calendar, Outlook Calendar, etc.)
   */
  calendarAccounts: defineTable({
    clerkUserId: v.string(),
    provider: v.union(
      v.literal("google"),
      v.literal("outlook"),
      v.literal("apple"),
      v.literal("caldav")
    ),
    status: v.union(
      v.literal("active"),
      v.literal("disconnected"),
      v.literal("error"),
      v.literal("pending")
    ),
    primaryEmail: v.string(),
    createdAt: v.number(),
  })
    .index("by_clerk_id", ["clerkUserId"])
    .index("by_clerk_id_provider", ["clerkUserId", "provider"])
    .index("by_status", ["status"]),

  // ============================================================================
  // Calendar System - Calendar Policies
  // ============================================================================
  /**
   * User's calendar scheduling policies and preferences
   */
  calendarPolicies: defineTable({
    clerkUserId: v.string(),
    /** Work hours configuration */
    workHours: v.object({
      timezone: v.string(),
      days: v.array(
        v.object({
          day: v.number(), // 0-6 (Sunday-Saturday)
          startHour: v.number(),
          startMinute: v.number(),
          endHour: v.number(),
          endMinute: v.number(),
        })
      ),
    }),
    /** Focus time blocks - protected time for deep work */
    focusBlocks: v.array(
      v.object({
        day: v.number(),
        startHour: v.number(),
        startMinute: v.number(),
        endHour: v.number(),
        endMinute: v.number(),
        label: v.optional(v.string()),
      })
    ),
    /** Meeting limits per day/week */
    meetingLimits: v.object({
      maxPerDay: v.optional(v.number()),
      maxPerWeek: v.optional(v.number()),
      maxConsecutiveMinutes: v.optional(v.number()),
      minBreakMinutes: v.optional(v.number()),
    }),
    /** Auto-apply flexible events without approval */
    autoApplyFlexible: v.boolean(),
    /** Auto-send approval requests for negotiable events */
    autoSendApprovals: v.boolean(),
    /** Apply reschedules immediately on approval */
    applyOnApproval: v.boolean(),
    updatedAt: v.number(),
  })
    .index("by_clerk_id", ["clerkUserId"]),

  // ============================================================================
  // Calendar System - Calendar Events
  // ============================================================================
  /**
   * Calendar events synced from external providers
   */
  calendarEvents: defineTable({
    clerkUserId: v.string(),
    accountId: v.id("calendarAccounts"),
    providerEventId: v.string(),
    title: v.string(),
    location: v.optional(v.string()),
    startAt: v.number(),
    endAt: v.number(),
    timezone: v.string(),
    attendees: v.array(
      v.object({
        email: v.string(),
        name: v.optional(v.string()),
        status: v.optional(
          v.union(
            v.literal("accepted"),
            v.literal("declined"),
            v.literal("tentative"),
            v.literal("needsAction")
          )
        ),
      })
    ),
    organizer: v.object({
      email: v.string(),
      name: v.optional(v.string()),
    }),
    visibility: v.union(
      v.literal("public"),
      v.literal("private"),
      v.literal("confidential")
    ),
    /** Event-specific policy overrides */
    policy: v.optional(
      v.object({
        lockState: v.union(
          v.literal("locked"),
          v.literal("flexible"),
          v.literal("negotiable"),
          v.literal("sensitive")
        ),
        movePermissions: v.union(
          v.literal("userOnly"),
          v.literal("organizerOnly"),
          v.literal("anyAttendee"),
          v.literal("specificApprover")
        ),
        requiresUserConfirmationBeforeSendingRequests: v.boolean(),
        contentSharing: v.union(
          v.literal("none"),
          v.literal("minimal"),
          v.literal("full")
        ),
        approver: v.optional(v.string()),
        allowedWindows: v.optional(
          v.array(
            v.object({
              startAt: v.number(),
              endAt: v.number(),
            })
          )
        ),
        maxShiftMinutes: v.optional(v.number()),
        maxShiftDays: v.optional(v.number()),
      })
    ),
    updatedAt: v.number(),
    deletedAt: v.optional(v.number()),
  })
    .index("by_clerk_id", ["clerkUserId"])
    .index("by_clerk_id_account", ["clerkUserId", "accountId"])
    .index("by_clerk_id_date_range", ["clerkUserId", "startAt", "endAt"])
    .index("by_account_provider_id", ["accountId", "providerEventId"])
    .index("by_clerk_id_updated", ["clerkUserId", "updatedAt"]),

  // ============================================================================
  // Calendar System - Calendar Tasks
  // ============================================================================
  /**
   * Tasks to be scheduled on the calendar
   */
  calendarTasks: defineTable({
    clerkUserId: v.string(),
    taskId: v.string(),
    title: v.string(),
    notes: v.optional(v.string()),
    durationMinutes: v.number(),
    dueAt: v.optional(v.number()),
    priority: v.union(
      v.literal("low"),
      v.literal("medium"),
      v.literal("high"),
      v.literal("urgent")
    ),
    dependencies: v.array(v.string()),
    chunkMinMinutes: v.optional(v.number()),
    status: v.union(
      v.literal("pending"),
      v.literal("scheduled"),
      v.literal("in_progress"),
      v.literal("completed"),
      v.literal("cancelled")
    ),
    updatedAt: v.number(),
  })
    .index("by_clerk_id", ["clerkUserId"])
    .index("by_clerk_id_status", ["clerkUserId", "status"])
    .index("by_clerk_id_due", ["clerkUserId", "dueAt"])
    .index("by_task_id", ["clerkUserId", "taskId"]),

  // ============================================================================
  // Calendar System - Reschedule Proposals
  // ============================================================================
  /**
   * Proposals for rescheduling events
   */
  rescheduleProposals: defineTable({
    clerkUserId: v.string(),
    eventId: v.id("calendarEvents"),
    createdBy: v.union(v.literal("user"), v.literal("brain"), v.literal("system")),
    status: v.union(
      v.literal("pending"),
      v.literal("approved"),
      v.literal("rejected"),
      v.literal("expired"),
      v.literal("applied")
    ),
    rationale: v.string(),
    options: v.array(
      v.object({
        startAt: v.number(),
        endAt: v.number(),
        score: v.optional(v.number()),
        reason: v.optional(v.string()),
      })
    ),
    requiresApprover: v.boolean(),
    approver: v.optional(v.string()),
    tokenHash: v.optional(v.string()),
    tokenExpiresAt: v.optional(v.number()),
    chosenOptionIndex: v.optional(v.number()),
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    .index("by_clerk_id", ["clerkUserId"])
    .index("by_clerk_id_status", ["clerkUserId", "status"])
    .index("by_event_id", ["eventId"])
    .index("by_token_hash", ["tokenHash"]),

  // ============================================================================
  // Calendar System - Approvals
  // ============================================================================
  /**
   * Approval decisions on reschedule proposals
   */
  approvals: defineTable({
    proposalId: v.id("rescheduleProposals"),
    actor: v.string(),
    decision: v.union(
      v.literal("approved"),
      v.literal("rejected"),
      v.literal("alternate")
    ),
    chosenOptionIndex: v.optional(v.number()),
    alternate: v.optional(
      v.object({
        startAt: v.number(),
        endAt: v.number(),
      })
    ),
    comment: v.optional(v.string()),
    createdAt: v.number(),
  })
    .index("by_proposal", ["proposalId"])
    .index("by_actor", ["actor"]),

  // ============================================================================
  // Calendar System - Notifications Outbox
  // ============================================================================
  /**
   * Outbound notifications queue for emails, push, etc.
   */
  notificationsOutbox: defineTable({
    clerkUserId: v.string(),
    channel: v.union(
      v.literal("email"),
      v.literal("push"),
      v.literal("sms"),
      v.literal("in_app")
    ),
    to: v.string(),
    templateId: v.string(),
    payload: v.any(),
    status: v.union(
      v.literal("pending"),
      v.literal("sent"),
      v.literal("failed"),
      v.literal("cancelled")
    ),
    attempts: v.number(),
    lastError: v.optional(v.string()),
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    .index("by_clerk_id", ["clerkUserId"])
    .index("by_status", ["status", "createdAt"])
    .index("by_status_attempts", ["status", "attempts"]),

  // ============================================================================
  // Calendar System - Tombstones
  // ============================================================================
  /**
   * Soft delete records for calendar entities
   */
  tombstones: defineTable({
    clerkUserId: v.string(),
    kind: v.union(
      v.literal("event"),
      v.literal("task"),
      v.literal("proposal"),
      v.literal("account")
    ),
    refId: v.string(),
    reason: v.optional(v.string()),
    createdAt: v.number(),
  })
    .index("by_clerk_id", ["clerkUserId"])
    .index("by_clerk_id_kind", ["clerkUserId", "kind"])
    .index("by_ref_id", ["refId"]),

  // ============================================================================
  // Calendar System - Brain Event Registry
  // ============================================================================
  /**
   * Registry of event types for Brain AI processing
   */
  brainEventRegistry: defineTable({
    eventType: v.string(),
    enabled: v.boolean(),
    requireRefs: v.array(v.string()),
    defaultBrainStatus: v.union(
      v.literal("pending"),
      v.literal("skipped")
    ),
    updatedAt: v.number(),
  })
    .index("by_event_type", ["eventType"])
    .index("by_enabled", ["enabled"]),
});
