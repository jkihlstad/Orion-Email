/**
 * Append-Only Event Log for Calendar Events
 *
 * This module provides functions for recording calendar-related events
 * in an append-only event store. Events are immutable - corrections
 * are recorded as new events rather than updates.
 *
 * Event Pattern:
 * - Events capture what happened, not commands
 * - brainStatus tracks AI processing status
 * - Idempotency keys prevent duplicate events
 * - Events are partitioned by clerkUserId for isolation
 *
 * Calendar Event Types:
 * - calendar.event.created: New event added
 * - calendar.event.updated: Event details changed
 * - calendar.event.deleted: Event removed
 * - calendar.event.rescheduled: Event time changed
 * - calendar.proposal.created: Reschedule proposal created
 * - calendar.proposal.approved: Proposal approved
 * - calendar.proposal.rejected: Proposal rejected
 * - calendar.proposal.applied: Approved proposal applied
 * - calendar.task.created: Task created
 * - calendar.task.updated: Task updated
 * - calendar.task.completed: Task marked complete
 * - calendar.sync.completed: Calendar sync finished
 */

import { mutation, query, internalMutation } from "../_generated/server";
import { v } from "convex/values";
import { Id } from "../_generated/dataModel";

// ============================================================================
// Types and Validators
// ============================================================================

/**
 * Calendar event types that can be appended
 */
const calendarEventTypeValidator = v.union(
  v.literal("calendar.event.created"),
  v.literal("calendar.event.updated"),
  v.literal("calendar.event.deleted"),
  v.literal("calendar.event.rescheduled"),
  v.literal("calendar.proposal.created"),
  v.literal("calendar.proposal.approved"),
  v.literal("calendar.proposal.rejected"),
  v.literal("calendar.proposal.applied"),
  v.literal("calendar.task.created"),
  v.literal("calendar.task.updated"),
  v.literal("calendar.task.completed"),
  v.literal("calendar.sync.completed"),
  v.literal("calendar.account.connected"),
  v.literal("calendar.account.disconnected"),
  v.literal("calendar.policy.updated")
);

export type CalendarEventType =
  | "calendar.event.created"
  | "calendar.event.updated"
  | "calendar.event.deleted"
  | "calendar.event.rescheduled"
  | "calendar.proposal.created"
  | "calendar.proposal.approved"
  | "calendar.proposal.rejected"
  | "calendar.proposal.applied"
  | "calendar.task.created"
  | "calendar.task.updated"
  | "calendar.task.completed"
  | "calendar.sync.completed"
  | "calendar.account.connected"
  | "calendar.account.disconnected"
  | "calendar.policy.updated";

const brainStatusValidator = v.union(
  v.literal("pending"),
  v.literal("processing"),
  v.literal("processed"),
  v.literal("failed"),
  v.literal("skipped")
);

export type BrainStatus = "pending" | "processing" | "processed" | "failed" | "skipped";

// ============================================================================
// Event Types Configuration
// ============================================================================

/**
 * Configuration for how each event type should be processed
 */
const eventTypeConfig: Record<
  CalendarEventType,
  { defaultBrainStatus: BrainStatus; description: string }
> = {
  "calendar.event.created": {
    defaultBrainStatus: "pending",
    description: "New calendar event was created",
  },
  "calendar.event.updated": {
    defaultBrainStatus: "pending",
    description: "Calendar event details were updated",
  },
  "calendar.event.deleted": {
    defaultBrainStatus: "skipped",
    description: "Calendar event was deleted",
  },
  "calendar.event.rescheduled": {
    defaultBrainStatus: "pending",
    description: "Calendar event was rescheduled",
  },
  "calendar.proposal.created": {
    defaultBrainStatus: "pending",
    description: "Reschedule proposal was created",
  },
  "calendar.proposal.approved": {
    defaultBrainStatus: "skipped",
    description: "Reschedule proposal was approved",
  },
  "calendar.proposal.rejected": {
    defaultBrainStatus: "skipped",
    description: "Reschedule proposal was rejected",
  },
  "calendar.proposal.applied": {
    defaultBrainStatus: "skipped",
    description: "Approved proposal was applied to event",
  },
  "calendar.task.created": {
    defaultBrainStatus: "pending",
    description: "New task was created",
  },
  "calendar.task.updated": {
    defaultBrainStatus: "pending",
    description: "Task was updated",
  },
  "calendar.task.completed": {
    defaultBrainStatus: "skipped",
    description: "Task was marked complete",
  },
  "calendar.sync.completed": {
    defaultBrainStatus: "skipped",
    description: "Calendar sync operation completed",
  },
  "calendar.account.connected": {
    defaultBrainStatus: "skipped",
    description: "Calendar account was connected",
  },
  "calendar.account.disconnected": {
    defaultBrainStatus: "skipped",
    description: "Calendar account was disconnected",
  },
  "calendar.policy.updated": {
    defaultBrainStatus: "skipped",
    description: "Calendar policy was updated",
  },
};

// ============================================================================
// Main Append Function
// ============================================================================

/**
 * Append a calendar event to the event log
 *
 * This is the primary function for recording calendar events.
 * All events are append-only - no updates allowed.
 *
 * @param clerkUserId - The user's Clerk ID
 * @param eventType - The type of calendar event
 * @param payload - The event data
 * @param brainStatus - Override the default brain status
 * @returns The created event record
 */
export const appendEvent = mutation({
  args: {
    clerkUserId: v.string(),
    eventType: calendarEventTypeValidator,
    payload: v.any(),
    brainStatus: v.optional(brainStatusValidator),
    idempotencyKey: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    // Check for duplicate if idempotency key provided
    if (args.idempotencyKey) {
      const existing = await ctx.db
        .query("events")
        .withIndex("by_idempotency", (q) =>
          q.eq("userId", args.clerkUserId).eq("idempotencyKey", args.idempotencyKey)
        )
        .unique();

      if (existing) {
        return { eventId: existing._id, deduplicated: true };
      }
    }

    const now = Date.now();

    // Determine brain status
    const config = eventTypeConfig[args.eventType];
    const brainStatus = args.brainStatus ?? config.defaultBrainStatus;

    // Insert the event
    const eventId = await ctx.db.insert("events", {
      userId: args.clerkUserId,
      type: args.eventType,
      payload: args.payload,
      timestamp: now,
      brainStatus,
      idempotencyKey: args.idempotencyKey,
    });

    return { eventId, deduplicated: false };
  },
});

// ============================================================================
// Specialized Append Functions
// ============================================================================

/**
 * Append event created log entry
 */
export const appendEventCreated = mutation({
  args: {
    clerkUserId: v.string(),
    eventId: v.id("calendarEvents"),
    title: v.string(),
    startAt: v.number(),
    endAt: v.number(),
    source: v.union(v.literal("sync"), v.literal("user"), v.literal("brain")),
    idempotencyKey: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { clerkUserId, idempotencyKey, ...payload } = args;

    return ctx.runMutation(api.events.append.appendEvent, {
      clerkUserId,
      eventType: "calendar.event.created",
      payload,
      idempotencyKey: idempotencyKey ?? `event_created_${payload.eventId}`,
    });
  },
});

/**
 * Append event rescheduled log entry
 */
export const appendEventRescheduled = mutation({
  args: {
    clerkUserId: v.string(),
    eventId: v.id("calendarEvents"),
    previousStartAt: v.number(),
    previousEndAt: v.number(),
    newStartAt: v.number(),
    newEndAt: v.number(),
    proposalId: v.optional(v.id("rescheduleProposals")),
    source: v.union(v.literal("user"), v.literal("brain"), v.literal("proposal")),
    idempotencyKey: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { clerkUserId, idempotencyKey, ...payload } = args;

    return ctx.runMutation(api.events.append.appendEvent, {
      clerkUserId,
      eventType: "calendar.event.rescheduled",
      payload,
      idempotencyKey,
    });
  },
});

/**
 * Append proposal created log entry
 */
export const appendProposalCreated = mutation({
  args: {
    clerkUserId: v.string(),
    proposalId: v.id("rescheduleProposals"),
    eventId: v.id("calendarEvents"),
    createdBy: v.union(v.literal("user"), v.literal("brain"), v.literal("system")),
    optionCount: v.number(),
    idempotencyKey: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { clerkUserId, idempotencyKey, ...payload } = args;

    return ctx.runMutation(api.events.append.appendEvent, {
      clerkUserId,
      eventType: "calendar.proposal.created",
      payload,
      idempotencyKey: idempotencyKey ?? `proposal_created_${payload.proposalId}`,
    });
  },
});

/**
 * Append proposal decision log entry
 */
export const appendProposalDecision = mutation({
  args: {
    clerkUserId: v.string(),
    proposalId: v.id("rescheduleProposals"),
    decision: v.union(
      v.literal("approved"),
      v.literal("rejected")
    ),
    actor: v.string(),
    chosenOptionIndex: v.optional(v.number()),
    idempotencyKey: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { clerkUserId, decision, idempotencyKey, ...payload } = args;

    const eventType =
      decision === "approved"
        ? "calendar.proposal.approved"
        : "calendar.proposal.rejected";

    return ctx.runMutation(api.events.append.appendEvent, {
      clerkUserId,
      eventType,
      payload: { ...payload, decision },
      idempotencyKey,
    });
  },
});

/**
 * Append task event log entry
 */
export const appendTaskEvent = mutation({
  args: {
    clerkUserId: v.string(),
    taskId: v.string(),
    eventType: v.union(
      v.literal("calendar.task.created"),
      v.literal("calendar.task.updated"),
      v.literal("calendar.task.completed")
    ),
    title: v.string(),
    changes: v.optional(v.any()),
    idempotencyKey: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { clerkUserId, eventType, idempotencyKey, ...payload } = args;

    return ctx.runMutation(api.events.append.appendEvent, {
      clerkUserId,
      eventType,
      payload,
      idempotencyKey,
    });
  },
});

/**
 * Append sync completed log entry
 */
export const appendSyncCompleted = mutation({
  args: {
    clerkUserId: v.string(),
    accountId: v.id("calendarAccounts"),
    eventsAdded: v.number(),
    eventsUpdated: v.number(),
    eventsDeleted: v.number(),
    syncDurationMs: v.number(),
    idempotencyKey: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { clerkUserId, idempotencyKey, ...payload } = args;

    return ctx.runMutation(api.events.append.appendEvent, {
      clerkUserId,
      eventType: "calendar.sync.completed",
      payload,
      brainStatus: "skipped",
      idempotencyKey,
    });
  },
});

// ============================================================================
// Query Functions
// ============================================================================

/**
 * Get calendar events for a user (paginated)
 */
export const getCalendarEventLog = query({
  args: {
    clerkUserId: v.string(),
    eventType: v.optional(calendarEventTypeValidator),
    since: v.optional(v.number()),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const limit = args.limit ?? 50;

    let queryBuilder;

    if (args.eventType) {
      queryBuilder = ctx.db
        .query("events")
        .withIndex("by_user_type", (q) =>
          q.eq("userId", args.clerkUserId).eq("type", args.eventType!)
        );
    } else {
      // Filter to only calendar events
      queryBuilder = ctx.db
        .query("events")
        .withIndex("by_user", (q) => q.eq("userId", args.clerkUserId))
        .filter((q) =>
          q.or(
            q.eq(q.field("type"), "calendar.event.created"),
            q.eq(q.field("type"), "calendar.event.updated"),
            q.eq(q.field("type"), "calendar.event.deleted"),
            q.eq(q.field("type"), "calendar.event.rescheduled"),
            q.eq(q.field("type"), "calendar.proposal.created"),
            q.eq(q.field("type"), "calendar.proposal.approved"),
            q.eq(q.field("type"), "calendar.proposal.rejected"),
            q.eq(q.field("type"), "calendar.proposal.applied"),
            q.eq(q.field("type"), "calendar.task.created"),
            q.eq(q.field("type"), "calendar.task.updated"),
            q.eq(q.field("type"), "calendar.task.completed"),
            q.eq(q.field("type"), "calendar.sync.completed"),
            q.eq(q.field("type"), "calendar.account.connected"),
            q.eq(q.field("type"), "calendar.account.disconnected"),
            q.eq(q.field("type"), "calendar.policy.updated")
          )
        );
    }

    if (args.since) {
      queryBuilder = queryBuilder.filter((q) =>
        q.gt(q.field("timestamp"), args.since!)
      );
    }

    const events = await queryBuilder.order("desc").take(limit + 1);

    const hasMore = events.length > limit;
    const items = hasMore ? events.slice(0, limit) : events;
    const nextCursor =
      hasMore && items.length > 0 ? items[items.length - 1].timestamp : null;

    return {
      items,
      nextCursor,
      hasMore,
    };
  },
});

/**
 * Get pending calendar events for Brain processing
 */
export const getPendingCalendarEvents = query({
  args: {
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const limit = args.limit ?? 100;

    return await ctx.db
      .query("events")
      .withIndex("by_brain_status", (q) => q.eq("brainStatus", "pending"))
      .filter((q) =>
        q.or(
          q.eq(q.field("type"), "calendar.event.created"),
          q.eq(q.field("type"), "calendar.event.updated"),
          q.eq(q.field("type"), "calendar.event.rescheduled"),
          q.eq(q.field("type"), "calendar.proposal.created"),
          q.eq(q.field("type"), "calendar.task.created"),
          q.eq(q.field("type"), "calendar.task.updated")
        )
      )
      .order("asc")
      .take(limit);
  },
});

// ============================================================================
// Internal Mutations
// ============================================================================

/**
 * Update brain status for a calendar event
 */
export const updateCalendarEventBrainStatus = internalMutation({
  args: {
    eventId: v.id("events"),
    brainStatus: brainStatusValidator,
    brainError: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const event = await ctx.db.get(args.eventId);
    if (!event) {
      throw new Error("Event not found");
    }

    await ctx.db.patch(args.eventId, {
      brainStatus: args.brainStatus,
      brainError: args.brainError,
      brainProcessedAt: args.brainStatus === "processed" ? Date.now() : undefined,
    });

    return { success: true };
  },
});

// Import for self-referential mutations
import { api } from "../_generated/api";
