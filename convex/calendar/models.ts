/**
 * Calendar Models and Validators
 *
 * This module exports Convex validators for calendar-related types.
 * These validators ensure type safety for mutations and queries.
 *
 * Key Types:
 * - LockState: Controls how strictly an event's time is protected
 * - MovePermissions: Who can approve event rescheduling
 * - ContentSharing: What event details can be shared externally
 * - EventPolicy: Complete policy configuration for an event
 */

import { v } from "convex/values";

// ============================================================================
// Lock State
// ============================================================================
/**
 * LockState determines how strictly an event's scheduled time is protected.
 *
 * - locked: Cannot be moved by Brain or auto-scheduling
 * - flexible: Can be moved freely by the system without approval
 * - negotiable: Can be moved but requires approval workflow
 * - sensitive: Event is private/sensitive, limited visibility in proposals
 */
export const LockStateValidator = v.union(
  v.literal("locked"),
  v.literal("flexible"),
  v.literal("negotiable"),
  v.literal("sensitive")
);

export type LockState = "locked" | "flexible" | "negotiable" | "sensitive";

// ============================================================================
// Move Permissions
// ============================================================================
/**
 * MovePermissions determines who can approve event rescheduling.
 *
 * - userOnly: Only the calendar owner can approve
 * - organizerOnly: Only the event organizer can approve
 * - anyAttendee: Any attendee can approve the reschedule
 * - specificApprover: A designated approver must approve
 */
export const MovePermissionsValidator = v.union(
  v.literal("userOnly"),
  v.literal("organizerOnly"),
  v.literal("anyAttendee"),
  v.literal("specificApprover")
);

export type MovePermissions =
  | "userOnly"
  | "organizerOnly"
  | "anyAttendee"
  | "specificApprover";

// ============================================================================
// Content Sharing
// ============================================================================
/**
 * ContentSharing determines what event details can be shared in proposals.
 *
 * - none: No event details shared (only time slots)
 * - minimal: Only title and duration shared
 * - full: All event details including attendees, description, etc.
 */
export const ContentSharingValidator = v.union(
  v.literal("none"),
  v.literal("minimal"),
  v.literal("full")
);

export type ContentSharing = "none" | "minimal" | "full";

// ============================================================================
// Event Policy
// ============================================================================
/**
 * EventPolicyValidator defines the complete policy configuration for an event.
 *
 * This controls:
 * - How the event can be rescheduled (lockState)
 * - Who can approve rescheduling (movePermissions)
 * - Whether user must confirm before requests are sent
 * - What content can be shared (contentSharing)
 * - Optional specific approver
 * - Allowed time windows for rescheduling
 * - Maximum time shift allowed
 */
export const EventPolicyValidator = v.object({
  /** How strictly the event time is protected */
  lockState: LockStateValidator,

  /** Who can approve rescheduling */
  movePermissions: MovePermissionsValidator,

  /** Require user confirmation before sending reschedule requests */
  requiresUserConfirmationBeforeSendingRequests: v.boolean(),

  /** What event details can be shared in proposals */
  contentSharing: ContentSharingValidator,

  /** Email of specific approver (when movePermissions is specificApprover) */
  approver: v.optional(v.string()),

  /** Allowed time windows for rescheduling */
  allowedWindows: v.optional(
    v.array(
      v.object({
        startAt: v.number(),
        endAt: v.number(),
      })
    )
  ),

  /** Maximum shift in minutes (for near-term adjustments) */
  maxShiftMinutes: v.optional(v.number()),

  /** Maximum shift in days (for longer-term rescheduling) */
  maxShiftDays: v.optional(v.number()),
});

export type EventPolicy = {
  lockState: LockState;
  movePermissions: MovePermissions;
  requiresUserConfirmationBeforeSendingRequests: boolean;
  contentSharing: ContentSharing;
  approver?: string;
  allowedWindows?: Array<{ startAt: number; endAt: number }>;
  maxShiftMinutes?: number;
  maxShiftDays?: number;
};

// ============================================================================
// Proposal Status
// ============================================================================
/**
 * ProposalStatus tracks the lifecycle of a reschedule proposal.
 */
export const ProposalStatusValidator = v.union(
  v.literal("pending"),
  v.literal("approved"),
  v.literal("rejected"),
  v.literal("expired"),
  v.literal("applied")
);

export type ProposalStatus =
  | "pending"
  | "approved"
  | "rejected"
  | "expired"
  | "applied";

// ============================================================================
// Proposal Creator
// ============================================================================
/**
 * Who created the reschedule proposal.
 */
export const ProposalCreatorValidator = v.union(
  v.literal("user"),
  v.literal("brain"),
  v.literal("system")
);

export type ProposalCreator = "user" | "brain" | "system";

// ============================================================================
// Approval Decision
// ============================================================================
/**
 * Decision made on a reschedule proposal.
 */
export const ApprovalDecisionValidator = v.union(
  v.literal("approved"),
  v.literal("rejected"),
  v.literal("alternate")
);

export type ApprovalDecision = "approved" | "rejected" | "alternate";

// ============================================================================
// Task Status
// ============================================================================
/**
 * Status of a calendar task.
 */
export const TaskStatusValidator = v.union(
  v.literal("pending"),
  v.literal("scheduled"),
  v.literal("in_progress"),
  v.literal("completed"),
  v.literal("cancelled")
);

export type TaskStatus =
  | "pending"
  | "scheduled"
  | "in_progress"
  | "completed"
  | "cancelled";

// ============================================================================
// Task Priority
// ============================================================================
/**
 * Priority level of a calendar task.
 */
export const TaskPriorityValidator = v.union(
  v.literal("low"),
  v.literal("medium"),
  v.literal("high"),
  v.literal("urgent")
);

export type TaskPriority = "low" | "medium" | "high" | "urgent";

// ============================================================================
// Notification Channel
// ============================================================================
/**
 * Channel for sending notifications.
 */
export const NotificationChannelValidator = v.union(
  v.literal("email"),
  v.literal("push"),
  v.literal("sms"),
  v.literal("in_app")
);

export type NotificationChannel = "email" | "push" | "sms" | "in_app";

// ============================================================================
// Attendee Status
// ============================================================================
/**
 * Response status of an event attendee.
 */
export const AttendeeStatusValidator = v.union(
  v.literal("accepted"),
  v.literal("declined"),
  v.literal("tentative"),
  v.literal("needsAction")
);

export type AttendeeStatus = "accepted" | "declined" | "tentative" | "needsAction";

// ============================================================================
// Event Visibility
// ============================================================================
/**
 * Visibility level of a calendar event.
 */
export const EventVisibilityValidator = v.union(
  v.literal("public"),
  v.literal("private"),
  v.literal("confidential")
);

export type EventVisibility = "public" | "private" | "confidential";

// ============================================================================
// Calendar Provider
// ============================================================================
/**
 * Supported calendar providers.
 */
export const CalendarProviderValidator = v.union(
  v.literal("google"),
  v.literal("outlook"),
  v.literal("apple"),
  v.literal("caldav")
);

export type CalendarProvider = "google" | "outlook" | "apple" | "caldav";

// ============================================================================
// Account Status
// ============================================================================
/**
 * Status of a calendar account connection.
 */
export const AccountStatusValidator = v.union(
  v.literal("active"),
  v.literal("disconnected"),
  v.literal("error"),
  v.literal("pending")
);

export type AccountStatus = "active" | "disconnected" | "error" | "pending";

// ============================================================================
// Tombstone Kind
// ============================================================================
/**
 * Type of entity that was soft-deleted.
 */
export const TombstoneKindValidator = v.union(
  v.literal("event"),
  v.literal("task"),
  v.literal("proposal"),
  v.literal("account")
);

export type TombstoneKind = "event" | "task" | "proposal" | "account";

// ============================================================================
// Composite Validators
// ============================================================================

/**
 * Attendee object validator
 */
export const AttendeeValidator = v.object({
  email: v.string(),
  name: v.optional(v.string()),
  status: v.optional(AttendeeStatusValidator),
});

/**
 * Organizer object validator
 */
export const OrganizerValidator = v.object({
  email: v.string(),
  name: v.optional(v.string()),
});

/**
 * Proposal option validator
 */
export const ProposalOptionValidator = v.object({
  startAt: v.number(),
  endAt: v.number(),
  score: v.optional(v.number()),
  reason: v.optional(v.string()),
});

/**
 * Time window validator
 */
export const TimeWindowValidator = v.object({
  startAt: v.number(),
  endAt: v.number(),
});

/**
 * Work day configuration validator
 */
export const WorkDayValidator = v.object({
  day: v.number(),
  startHour: v.number(),
  startMinute: v.number(),
  endHour: v.number(),
  endMinute: v.number(),
});

/**
 * Focus block validator
 */
export const FocusBlockValidator = v.object({
  day: v.number(),
  startHour: v.number(),
  startMinute: v.number(),
  endHour: v.number(),
  endMinute: v.number(),
  label: v.optional(v.string()),
});

/**
 * Meeting limits validator
 */
export const MeetingLimitsValidator = v.object({
  maxPerDay: v.optional(v.number()),
  maxPerWeek: v.optional(v.number()),
  maxConsecutiveMinutes: v.optional(v.number()),
  minBreakMinutes: v.optional(v.number()),
});

/**
 * Work hours validator
 */
export const WorkHoursValidator = v.object({
  timezone: v.string(),
  days: v.array(WorkDayValidator),
});
