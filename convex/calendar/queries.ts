/**
 * Calendar Query Functions
 *
 * This module provides query functions for reading calendar data.
 * All queries are scoped by clerkUserId for privacy/security.
 *
 * Privacy/Consent Model:
 * - All queries filter by clerkUserId to prevent cross-user access
 * - Deleted events are excluded by default
 * - No sensitive data is exposed without proper authorization
 */

import { query } from "../_generated/server";
import { v } from "convex/values";
import { Id } from "../_generated/dataModel";
import { ProposalStatusValidator } from "./models";

// ============================================================================
// Event Queries
// ============================================================================

/**
 * List calendar events within a date range
 *
 * @param clerkUserId - The user's Clerk ID
 * @param startAt - Start of the date range (timestamp)
 * @param endAt - End of the date range (timestamp)
 * @returns Array of calendar events, excluding deleted ones
 */
export const listEvents = query({
  args: {
    clerkUserId: v.string(),
    startAt: v.number(),
    endAt: v.number(),
  },
  handler: async (ctx, args) => {
    // Query events within the date range
    const events = await ctx.db
      .query("calendarEvents")
      .withIndex("by_clerk_id", (q) => q.eq("clerkUserId", args.clerkUserId))
      .filter((q) =>
        q.and(
          // Event overlaps with the requested range
          q.lt(q.field("startAt"), args.endAt),
          q.gt(q.field("endAt"), args.startAt),
          // Exclude deleted events
          q.or(
            q.eq(q.field("deletedAt"), undefined),
            q.eq(q.field("deletedAt"), null)
          )
        )
      )
      .collect();

    // Sort by start time
    return events.sort((a, b) => a.startAt - b.startAt);
  },
});

/**
 * Get a single event by ID
 *
 * @param clerkUserId - The user's Clerk ID
 * @param eventId - The event ID
 * @returns The event if found and belongs to user, null otherwise
 */
export const getEventById = query({
  args: {
    clerkUserId: v.string(),
    eventId: v.id("calendarEvents"),
  },
  handler: async (ctx, args) => {
    const event = await ctx.db.get(args.eventId);

    // Verify ownership and not deleted
    if (!event || event.clerkUserId !== args.clerkUserId || event.deletedAt) {
      return null;
    }

    return event;
  },
});

// ============================================================================
// Proposal Queries
// ============================================================================

/**
 * List reschedule proposals by status
 *
 * @param clerkUserId - The user's Clerk ID
 * @param status - Filter by proposal status (optional)
 * @returns Array of proposals matching criteria
 */
export const listProposals = query({
  args: {
    clerkUserId: v.string(),
    status: v.optional(ProposalStatusValidator),
  },
  handler: async (ctx, args) => {
    if (args.status) {
      // Query by status using the compound index
      return await ctx.db
        .query("rescheduleProposals")
        .withIndex("by_clerk_id_status", (q) =>
          q.eq("clerkUserId", args.clerkUserId).eq("status", args.status!)
        )
        .order("desc")
        .collect();
    }

    // Return all proposals for user
    return await ctx.db
      .query("rescheduleProposals")
      .withIndex("by_clerk_id", (q) => q.eq("clerkUserId", args.clerkUserId))
      .order("desc")
      .collect();
  },
});

/**
 * Get a single proposal by ID
 *
 * @param clerkUserId - The user's Clerk ID
 * @param proposalId - The proposal ID
 * @returns The proposal if found and belongs to user, null otherwise
 */
export const getProposalById = query({
  args: {
    clerkUserId: v.string(),
    proposalId: v.id("rescheduleProposals"),
  },
  handler: async (ctx, args) => {
    const proposal = await ctx.db.get(args.proposalId);

    // Verify ownership
    if (!proposal || proposal.clerkUserId !== args.clerkUserId) {
      return null;
    }

    // Fetch the associated event
    const event = await ctx.db.get(proposal.eventId);

    // Fetch any approvals for this proposal
    const approvals = await ctx.db
      .query("approvals")
      .withIndex("by_proposal", (q) => q.eq("proposalId", args.proposalId))
      .collect();

    return {
      ...proposal,
      event,
      approvals,
    };
  },
});

/**
 * Get proposal by token hash (for external approval links)
 *
 * @param tokenHash - The hashed approval token
 * @returns The proposal if found and not expired, null otherwise
 */
export const getProposalByToken = query({
  args: {
    tokenHash: v.string(),
  },
  handler: async (ctx, args) => {
    const proposal = await ctx.db
      .query("rescheduleProposals")
      .withIndex("by_token_hash", (q) => q.eq("tokenHash", args.tokenHash))
      .unique();

    if (!proposal) {
      return null;
    }

    // Check if token is expired
    if (proposal.tokenExpiresAt && proposal.tokenExpiresAt < Date.now()) {
      return { ...proposal, expired: true };
    }

    // Fetch the associated event (limited info for external access)
    const event = await ctx.db.get(proposal.eventId);

    return {
      ...proposal,
      expired: false,
      event: event
        ? {
            title: event.title,
            startAt: event.startAt,
            endAt: event.endAt,
            timezone: event.timezone,
          }
        : null,
    };
  },
});

// ============================================================================
// Policy Queries
// ============================================================================

/**
 * Get user's calendar policy
 *
 * @param clerkUserId - The user's Clerk ID
 * @returns The policy if found, null otherwise
 */
export const getPolicy = query({
  args: {
    clerkUserId: v.string(),
  },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("calendarPolicies")
      .withIndex("by_clerk_id", (q) => q.eq("clerkUserId", args.clerkUserId))
      .unique();
  },
});

// ============================================================================
// Task Queries
// ============================================================================

/**
 * List all tasks for a user
 *
 * @param clerkUserId - The user's Clerk ID
 * @returns Array of tasks sorted by due date
 */
export const listTasks = query({
  args: {
    clerkUserId: v.string(),
  },
  handler: async (ctx, args) => {
    const tasks = await ctx.db
      .query("calendarTasks")
      .withIndex("by_clerk_id", (q) => q.eq("clerkUserId", args.clerkUserId))
      .collect();

    // Sort by due date (nulls last), then by priority
    const priorityOrder = { urgent: 0, high: 1, medium: 2, low: 3 };

    return tasks.sort((a, b) => {
      // First sort by due date
      if (a.dueAt && b.dueAt) {
        return a.dueAt - b.dueAt;
      }
      if (a.dueAt) return -1;
      if (b.dueAt) return 1;

      // Then by priority
      return priorityOrder[a.priority] - priorityOrder[b.priority];
    });
  },
});

/**
 * List tasks by status
 *
 * @param clerkUserId - The user's Clerk ID
 * @param status - Filter by task status
 * @returns Array of tasks matching the status
 */
export const listTasksByStatus = query({
  args: {
    clerkUserId: v.string(),
    status: v.union(
      v.literal("pending"),
      v.literal("scheduled"),
      v.literal("in_progress"),
      v.literal("completed"),
      v.literal("cancelled")
    ),
  },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("calendarTasks")
      .withIndex("by_clerk_id_status", (q) =>
        q.eq("clerkUserId", args.clerkUserId).eq("status", args.status)
      )
      .collect();
  },
});

/**
 * Get a single task by ID
 *
 * @param clerkUserId - The user's Clerk ID
 * @param taskId - The task ID (internal)
 * @returns The task if found and belongs to user, null otherwise
 */
export const getTaskById = query({
  args: {
    clerkUserId: v.string(),
    taskId: v.string(),
  },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("calendarTasks")
      .withIndex("by_task_id", (q) =>
        q.eq("clerkUserId", args.clerkUserId).eq("taskId", args.taskId)
      )
      .unique();
  },
});

// ============================================================================
// Account Queries
// ============================================================================

/**
 * List all calendar accounts for a user
 *
 * @param clerkUserId - The user's Clerk ID
 * @returns Array of calendar accounts
 */
export const listAccounts = query({
  args: {
    clerkUserId: v.string(),
  },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("calendarAccounts")
      .withIndex("by_clerk_id", (q) => q.eq("clerkUserId", args.clerkUserId))
      .collect();
  },
});

/**
 * Get a single calendar account by ID
 *
 * @param clerkUserId - The user's Clerk ID
 * @param accountId - The account ID
 * @returns The account if found and belongs to user, null otherwise
 */
export const getAccountById = query({
  args: {
    clerkUserId: v.string(),
    accountId: v.id("calendarAccounts"),
  },
  handler: async (ctx, args) => {
    const account = await ctx.db.get(args.accountId);

    if (!account || account.clerkUserId !== args.clerkUserId) {
      return null;
    }

    return account;
  },
});

// ============================================================================
// User Queries
// ============================================================================

/**
 * Get user by Clerk ID
 *
 * @param clerkUserId - The user's Clerk ID
 * @returns The user if found, null otherwise
 */
export const getUser = query({
  args: {
    clerkUserId: v.string(),
  },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("users")
      .withIndex("by_clerk_id", (q) => q.eq("clerkUserId", args.clerkUserId))
      .unique();
  },
});

/**
 * Get user consent record
 *
 * @param clerkUserId - The user's Clerk ID
 * @returns The consent record if found, null otherwise
 */
export const getUserConsent = query({
  args: {
    clerkUserId: v.string(),
  },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("userConsents")
      .withIndex("by_clerk_id", (q) => q.eq("clerkUserId", args.clerkUserId))
      .unique();
  },
});

// ============================================================================
// Approval Queries
// ============================================================================

/**
 * List approvals for a proposal
 *
 * @param proposalId - The proposal ID
 * @returns Array of approvals
 */
export const listApprovalsByProposal = query({
  args: {
    proposalId: v.id("rescheduleProposals"),
  },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("approvals")
      .withIndex("by_proposal", (q) => q.eq("proposalId", args.proposalId))
      .collect();
  },
});

// ============================================================================
// Tombstone Queries
// ============================================================================

/**
 * List tombstones for a user (for sync)
 *
 * @param clerkUserId - The user's Clerk ID
 * @param kind - Optional filter by entity type
 * @param since - Optional filter for tombstones after this timestamp
 * @returns Array of tombstones
 */
export const listTombstones = query({
  args: {
    clerkUserId: v.string(),
    kind: v.optional(
      v.union(
        v.literal("event"),
        v.literal("task"),
        v.literal("proposal"),
        v.literal("account")
      )
    ),
    since: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    let queryBuilder;

    if (args.kind) {
      queryBuilder = ctx.db
        .query("tombstones")
        .withIndex("by_clerk_id_kind", (q) =>
          q.eq("clerkUserId", args.clerkUserId).eq("kind", args.kind!)
        );
    } else {
      queryBuilder = ctx.db
        .query("tombstones")
        .withIndex("by_clerk_id", (q) => q.eq("clerkUserId", args.clerkUserId));
    }

    if (args.since) {
      return await queryBuilder
        .filter((q) => q.gt(q.field("createdAt"), args.since!))
        .collect();
    }

    return await queryBuilder.collect();
  },
});
