/**
 * Event Ingestion Helpers for Email Events
 *
 * This module provides helpers for appending events to the append-only event store.
 * All events are immutable - corrections are new events, not updates.
 *
 * Event Pattern:
 * - Events capture what happened, not commands
 * - brainStatus tracks AI processing status
 * - Idempotency keys prevent duplicate events
 * - Events are partitioned by userId for isolation
 *
 * Privacy/Consent Model:
 * - All events are scoped to a single user
 * - Brain processing can be skipped based on consent
 * - Events provide audit trail for compliance
 */

import { mutation, internalMutation, query } from "../_generated/server";
import { v } from "convex/values";
import { Id } from "../_generated/dataModel";
import type { EmailEventType, BrainStatus } from "../email/types";

// ============================================================================
// Types
// ============================================================================

/**
 * Base event payload structure
 */
interface BaseEventPayload {
  accountId?: Id<"emailAccounts">;
  [key: string]: unknown;
}

/**
 * Message received event payload
 */
interface MessageReceivedPayload extends BaseEventPayload {
  messageId: string;
  threadId: string;
  from: { email: string; name?: string };
  subject: string;
  hasAttachments: boolean;
}

/**
 * Message sent event payload
 */
interface MessageSentPayload extends BaseEventPayload {
  draftId?: Id<"emailDrafts">;
  to: Array<{ email: string; name?: string }>;
  cc?: Array<{ email: string; name?: string }>;
  bcc?: Array<{ email: string; name?: string }>;
  subject: string;
  body: string;
  htmlBody?: string;
  replyToMessageId?: string;
  forwardFromMessageId?: string;
  status: "queued" | "sent" | "failed";
  errorMessage?: string;
}

/**
 * Thread updated event payload
 */
interface ThreadUpdatedPayload extends BaseEventPayload {
  threadId: string;
  changes: {
    labels?: string[];
    isStarred?: boolean;
    unreadCount?: number;
  };
}

/**
 * Action applied event payload
 */
interface ActionAppliedPayload extends BaseEventPayload {
  threadId: string;
  action: string;
  labelId?: string;
}

// ============================================================================
// Event Validators
// ============================================================================

const emailEventTypeValidator = v.union(
  v.literal("email.message.received"),
  v.literal("email.message.sent"),
  v.literal("email.thread.updated"),
  v.literal("email.action.applied"),
  v.literal("email.draft.created"),
  v.literal("email.draft.updated"),
  v.literal("email.draft.deleted"),
  v.literal("email.label.created"),
  v.literal("email.label.deleted"),
  v.literal("email.account.connected"),
  v.literal("email.account.disconnected"),
  v.literal("email.sync.completed")
);

const brainStatusValidator = v.union(
  v.literal("pending"),
  v.literal("processing"),
  v.literal("processed"),
  v.literal("failed"),
  v.literal("skipped")
);

// ============================================================================
// Generic Event Appender
// ============================================================================

/**
 * Append a generic email event to the event store
 *
 * This is the primary function for recording events.
 * All events are append-only - no updates allowed.
 */
export const appendEmailEvent = mutation({
  args: {
    userId: v.string(),
    type: emailEventTypeValidator,
    payload: v.any(),
    /** Set initial brain status (default: pending) */
    brainStatus: v.optional(brainStatusValidator),
    /** Idempotency key for deduplication */
    idempotencyKey: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    // Check for duplicate if idempotency key provided
    if (args.idempotencyKey) {
      const existing = await ctx.db
        .query("events")
        .withIndex("by_idempotency", (q) =>
          q.eq("userId", args.userId).eq("idempotencyKey", args.idempotencyKey)
        )
        .unique();

      if (existing) {
        // Return existing event ID (idempotent)
        return { eventId: existing._id, deduplicated: true };
      }
    }

    const now = Date.now();

    // Determine brain status based on event type
    let brainStatus = args.brainStatus ?? "pending";

    // Some events don't need brain processing
    const skipBrainEvents: EmailEventType[] = [
      "email.draft.created",
      "email.draft.updated",
      "email.draft.deleted",
      "email.label.created",
      "email.label.deleted",
      "email.account.connected",
      "email.account.disconnected",
      "email.sync.completed",
    ];

    if (skipBrainEvents.includes(args.type as EmailEventType)) {
      brainStatus = "skipped";
    }

    // Insert the event
    const eventId = await ctx.db.insert("events", {
      userId: args.userId,
      type: args.type,
      payload: args.payload,
      timestamp: now,
      brainStatus: brainStatus as BrainStatus,
      idempotencyKey: args.idempotencyKey,
    });

    return { eventId, deduplicated: false };
  },
});

// ============================================================================
// Specialized Event Appenders
// ============================================================================

/**
 * Append a message received event
 * These events are queued for Brain processing (sentiment, categorization, etc.)
 */
export const appendMessageReceivedEvent = mutation({
  args: {
    userId: v.string(),
    accountId: v.id("emailAccounts"),
    messageId: v.string(),
    threadId: v.string(),
    from: v.object({
      email: v.string(),
      name: v.optional(v.string()),
    }),
    subject: v.string(),
    hasAttachments: v.boolean(),
    idempotencyKey: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    // Use message ID as default idempotency key
    const idempotencyKey = args.idempotencyKey ?? `msg_received_${args.messageId}`;

    // Check for duplicate
    const existing = await ctx.db
      .query("events")
      .withIndex("by_idempotency", (q) =>
        q.eq("userId", args.userId).eq("idempotencyKey", idempotencyKey)
      )
      .unique();

    if (existing) {
      return { eventId: existing._id, deduplicated: true };
    }

    const eventId = await ctx.db.insert("events", {
      userId: args.userId,
      type: "email.message.received",
      payload: {
        accountId: args.accountId,
        messageId: args.messageId,
        threadId: args.threadId,
        from: args.from,
        subject: args.subject,
        hasAttachments: args.hasAttachments,
      },
      timestamp: Date.now(),
      brainStatus: "pending",
      idempotencyKey,
    });

    return { eventId, deduplicated: false };
  },
});

/**
 * Append a message sent event
 * Used when user sends an email
 */
export const appendMessageSentEvent = mutation({
  args: {
    userId: v.string(),
    accountId: v.id("emailAccounts"),
    draftId: v.optional(v.id("emailDrafts")),
    to: v.array(
      v.object({
        email: v.string(),
        name: v.optional(v.string()),
      })
    ),
    cc: v.optional(
      v.array(
        v.object({
          email: v.string(),
          name: v.optional(v.string()),
        })
      )
    ),
    bcc: v.optional(
      v.array(
        v.object({
          email: v.string(),
          name: v.optional(v.string()),
        })
      )
    ),
    subject: v.string(),
    status: v.union(v.literal("queued"), v.literal("sent"), v.literal("failed")),
    errorMessage: v.optional(v.string()),
    idempotencyKey: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    // Check for duplicate
    if (args.idempotencyKey) {
      const existing = await ctx.db
        .query("events")
        .withIndex("by_idempotency", (q) =>
          q.eq("userId", args.userId).eq("idempotencyKey", args.idempotencyKey)
        )
        .unique();

      if (existing) {
        return { eventId: existing._id, deduplicated: true };
      }
    }

    const eventId = await ctx.db.insert("events", {
      userId: args.userId,
      type: "email.message.sent",
      payload: {
        accountId: args.accountId,
        draftId: args.draftId,
        to: args.to,
        cc: args.cc,
        bcc: args.bcc,
        subject: args.subject,
        status: args.status,
        errorMessage: args.errorMessage,
      },
      timestamp: Date.now(),
      brainStatus: "pending",
      idempotencyKey: args.idempotencyKey,
    });

    return { eventId, deduplicated: false };
  },
});

/**
 * Append a thread updated event
 */
export const appendThreadUpdatedEvent = mutation({
  args: {
    userId: v.string(),
    accountId: v.id("emailAccounts"),
    threadId: v.string(),
    changes: v.object({
      labels: v.optional(v.array(v.string())),
      isStarred: v.optional(v.boolean()),
      unreadCount: v.optional(v.number()),
    }),
    idempotencyKey: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    if (args.idempotencyKey) {
      const existing = await ctx.db
        .query("events")
        .withIndex("by_idempotency", (q) =>
          q.eq("userId", args.userId).eq("idempotencyKey", args.idempotencyKey)
        )
        .unique();

      if (existing) {
        return { eventId: existing._id, deduplicated: true };
      }
    }

    const eventId = await ctx.db.insert("events", {
      userId: args.userId,
      type: "email.thread.updated",
      payload: {
        accountId: args.accountId,
        threadId: args.threadId,
        changes: args.changes,
      },
      timestamp: Date.now(),
      brainStatus: "pending",
      idempotencyKey: args.idempotencyKey,
    });

    return { eventId, deduplicated: false };
  },
});

/**
 * Append an action applied event
 */
export const appendActionAppliedEvent = mutation({
  args: {
    userId: v.string(),
    accountId: v.id("emailAccounts"),
    threadId: v.string(),
    action: v.string(),
    labelId: v.optional(v.string()),
    idempotencyKey: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    if (args.idempotencyKey) {
      const existing = await ctx.db
        .query("events")
        .withIndex("by_idempotency", (q) =>
          q.eq("userId", args.userId).eq("idempotencyKey", args.idempotencyKey)
        )
        .unique();

      if (existing) {
        return { eventId: existing._id, deduplicated: true };
      }
    }

    const eventId = await ctx.db.insert("events", {
      userId: args.userId,
      type: "email.action.applied",
      payload: {
        accountId: args.accountId,
        threadId: args.threadId,
        action: args.action,
        labelId: args.labelId,
      },
      timestamp: Date.now(),
      brainStatus: "pending",
      idempotencyKey: args.idempotencyKey,
    });

    return { eventId, deduplicated: false };
  },
});

// ============================================================================
// Event Queries (for Brain processing)
// ============================================================================

/**
 * Get pending events for Brain processing
 */
export const getPendingEvents = query({
  args: {
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const limit = args.limit ?? 100;

    const events = await ctx.db
      .query("events")
      .withIndex("by_brain_status", (q) => q.eq("brainStatus", "pending"))
      .order("asc")
      .take(limit);

    return events;
  },
});

/**
 * Get events by user and type
 */
export const getEventsByType = query({
  args: {
    userId: v.string(),
    type: emailEventTypeValidator,
    since: v.optional(v.number()),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const limit = args.limit ?? 100;

    let query = ctx.db
      .query("events")
      .withIndex("by_user_type", (q) =>
        q.eq("userId", args.userId).eq("type", args.type)
      )
      .order("desc");

    if (args.since) {
      query = query.filter((q) => q.gt(q.field("timestamp"), args.since!));
    }

    const events = await query.take(limit);

    return events;
  },
});

/**
 * Get all events for a user (paginated)
 */
export const getUserEvents = query({
  args: {
    userId: v.string(),
    cursor: v.optional(v.number()),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const limit = args.limit ?? 50;

    let query = ctx.db
      .query("events")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .order("desc");

    if (args.cursor) {
      query = query.filter((q) => q.lt(q.field("timestamp"), args.cursor!));
    }

    const events = await query.take(limit + 1);

    const hasMore = events.length > limit;
    const items = hasMore ? events.slice(0, limit) : events;
    const nextCursor = hasMore && items.length > 0
      ? items[items.length - 1].timestamp
      : null;

    return {
      items,
      nextCursor,
      hasMore,
    };
  },
});

// ============================================================================
// Internal Mutations (for Brain/system use)
// ============================================================================

/**
 * Update brain status for an event
 * Used by Brain workers after processing
 */
export const updateBrainStatus = internalMutation({
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
      brainStatus: args.brainStatus as BrainStatus,
      brainError: args.brainError,
      brainProcessedAt: args.brainStatus === "processed" ? Date.now() : undefined,
    });

    return { success: true };
  },
});

/**
 * Mark event as processing (claim for worker)
 */
export const claimEventForProcessing = internalMutation({
  args: {
    eventId: v.id("events"),
  },
  handler: async (ctx, args) => {
    const event = await ctx.db.get(args.eventId);
    if (!event) {
      throw new Error("Event not found");
    }

    // Only claim if still pending
    if (event.brainStatus !== "pending") {
      return { claimed: false, currentStatus: event.brainStatus };
    }

    await ctx.db.patch(args.eventId, {
      brainStatus: "processing",
    });

    return { claimed: true, event };
  },
});

/**
 * Batch claim events for processing
 */
export const batchClaimEventsForProcessing = internalMutation({
  args: {
    eventIds: v.array(v.id("events")),
  },
  handler: async (ctx, args) => {
    const claimed: Id<"events">[] = [];

    for (const eventId of args.eventIds) {
      const event = await ctx.db.get(eventId);
      if (event && event.brainStatus === "pending") {
        await ctx.db.patch(eventId, {
          brainStatus: "processing",
        });
        claimed.push(eventId);
      }
    }

    return { claimedCount: claimed.length, claimedIds: claimed };
  },
});

/**
 * Reset stuck processing events
 * Call this periodically to handle crashed workers
 */
export const resetStuckEvents = internalMutation({
  args: {
    /** Events processing for longer than this (ms) are considered stuck */
    stuckThreshold: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const threshold = args.stuckThreshold ?? 5 * 60 * 1000; // 5 minutes default
    const cutoff = Date.now() - threshold;

    // Find events stuck in processing
    const stuckEvents = await ctx.db
      .query("events")
      .withIndex("by_brain_status", (q) => q.eq("brainStatus", "processing"))
      .filter((q) => q.lt(q.field("timestamp"), cutoff))
      .take(100);

    let resetCount = 0;
    for (const event of stuckEvents) {
      await ctx.db.patch(event._id, {
        brainStatus: "pending",
      });
      resetCount++;
    }

    return { resetCount };
  },
});

// ============================================================================
// Correction Events
// ============================================================================

/**
 * Append a correction event
 * When data needs to be corrected, we append a new event rather than update
 */
export const appendCorrectionEvent = mutation({
  args: {
    userId: v.string(),
    originalEventId: v.id("events"),
    correctionType: v.string(),
    correctionPayload: v.any(),
    reason: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    // Verify original event exists and belongs to user
    const originalEvent = await ctx.db.get(args.originalEventId);
    if (!originalEvent || originalEvent.userId !== args.userId) {
      throw new Error("Original event not found or access denied");
    }

    const eventId = await ctx.db.insert("events", {
      userId: args.userId,
      type: `${originalEvent.type}.correction` as any,
      payload: {
        originalEventId: args.originalEventId,
        originalType: originalEvent.type,
        correctionType: args.correctionType,
        correctionPayload: args.correctionPayload,
        reason: args.reason,
      },
      timestamp: Date.now(),
      brainStatus: "pending",
    });

    return { eventId };
  },
});
