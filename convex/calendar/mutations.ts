/**
 * Calendar Mutation Functions
 *
 * This module provides mutation functions for modifying calendar data.
 * All mutations are scoped by clerkUserId for privacy/security.
 *
 * Privacy/Consent Model:
 * - All mutations verify clerkUserId ownership before modification
 * - Soft deletes are used where appropriate (tombstones)
 * - Audit trail is maintained through timestamps
 */

import { mutation, internalMutation } from "../_generated/server";
import { v } from "convex/values";
import { Id } from "../_generated/dataModel";
import {
  EventPolicyValidator,
  ProposalStatusValidator,
  ProposalCreatorValidator,
  ApprovalDecisionValidator,
  TaskStatusValidator,
  TaskPriorityValidator,
  AttendeeValidator,
  OrganizerValidator,
  EventVisibilityValidator,
  ProposalOptionValidator,
  WorkHoursValidator,
  FocusBlockValidator,
  MeetingLimitsValidator,
} from "./models";

// ============================================================================
// Event Mutations
// ============================================================================

/**
 * Upsert events in batch from sync
 *
 * @param clerkUserId - The user's Clerk ID
 * @param accountId - The calendar account ID
 * @param events - Array of events to upsert
 * @returns Object with counts of inserted and updated events
 */
export const upsertEventsBatch = mutation({
  args: {
    clerkUserId: v.string(),
    accountId: v.id("calendarAccounts"),
    events: v.array(
      v.object({
        providerEventId: v.string(),
        title: v.string(),
        location: v.optional(v.string()),
        startAt: v.number(),
        endAt: v.number(),
        timezone: v.string(),
        attendees: v.array(AttendeeValidator),
        organizer: OrganizerValidator,
        visibility: EventVisibilityValidator,
        policy: v.optional(EventPolicyValidator),
      })
    ),
  },
  handler: async (ctx, args) => {
    // Verify account ownership
    const account = await ctx.db.get(args.accountId);
    if (!account || account.clerkUserId !== args.clerkUserId) {
      throw new Error("Account not found or access denied");
    }

    let insertedCount = 0;
    let updatedCount = 0;
    const now = Date.now();

    for (const event of args.events) {
      // Check if event already exists
      const existing = await ctx.db
        .query("calendarEvents")
        .withIndex("by_account_provider_id", (q) =>
          q
            .eq("accountId", args.accountId)
            .eq("providerEventId", event.providerEventId)
        )
        .unique();

      if (existing) {
        // Update existing event
        await ctx.db.patch(existing._id, {
          title: event.title,
          location: event.location,
          startAt: event.startAt,
          endAt: event.endAt,
          timezone: event.timezone,
          attendees: event.attendees,
          organizer: event.organizer,
          visibility: event.visibility,
          policy: event.policy,
          updatedAt: now,
        });
        updatedCount++;
      } else {
        // Insert new event
        await ctx.db.insert("calendarEvents", {
          clerkUserId: args.clerkUserId,
          accountId: args.accountId,
          providerEventId: event.providerEventId,
          title: event.title,
          location: event.location,
          startAt: event.startAt,
          endAt: event.endAt,
          timezone: event.timezone,
          attendees: event.attendees,
          organizer: event.organizer,
          visibility: event.visibility,
          policy: event.policy,
          updatedAt: now,
        });
        insertedCount++;
      }
    }

    return { insertedCount, updatedCount };
  },
});

/**
 * Update event policy
 *
 * @param clerkUserId - The user's Clerk ID
 * @param eventId - The event ID
 * @param policy - The new policy settings
 * @returns The updated event
 */
export const updateEventPolicy = mutation({
  args: {
    clerkUserId: v.string(),
    eventId: v.id("calendarEvents"),
    policy: EventPolicyValidator,
  },
  handler: async (ctx, args) => {
    // Verify ownership
    const event = await ctx.db.get(args.eventId);
    if (!event || event.clerkUserId !== args.clerkUserId) {
      throw new Error("Event not found or access denied");
    }

    await ctx.db.patch(args.eventId, {
      policy: args.policy,
      updatedAt: Date.now(),
    });

    return await ctx.db.get(args.eventId);
  },
});

/**
 * Soft delete an event
 *
 * @param clerkUserId - The user's Clerk ID
 * @param eventId - The event ID
 * @returns Success status
 */
export const deleteEvent = mutation({
  args: {
    clerkUserId: v.string(),
    eventId: v.id("calendarEvents"),
  },
  handler: async (ctx, args) => {
    const event = await ctx.db.get(args.eventId);
    if (!event || event.clerkUserId !== args.clerkUserId) {
      throw new Error("Event not found or access denied");
    }

    const now = Date.now();

    // Soft delete
    await ctx.db.patch(args.eventId, {
      deletedAt: now,
      updatedAt: now,
    });

    // Create tombstone
    await ctx.db.insert("tombstones", {
      clerkUserId: args.clerkUserId,
      kind: "event",
      refId: args.eventId,
      reason: "user_deleted",
      createdAt: now,
    });

    return { success: true };
  },
});

// ============================================================================
// Proposal Mutations
// ============================================================================

/**
 * Create a reschedule proposal
 *
 * @param clerkUserId - The user's Clerk ID
 * @param eventId - The event to reschedule
 * @param createdBy - Who created the proposal
 * @param rationale - Reason for rescheduling
 * @param options - Array of time slot options
 * @param requiresApprover - Whether external approval is needed
 * @param approver - Email of approver (if required)
 * @param tokenHash - Hashed approval token (for email links)
 * @param tokenExpiresAt - Token expiration timestamp
 * @param status - Initial status (default: pending)
 * @returns The created proposal
 */
export const createProposal = mutation({
  args: {
    clerkUserId: v.string(),
    eventId: v.id("calendarEvents"),
    createdBy: ProposalCreatorValidator,
    rationale: v.string(),
    options: v.array(ProposalOptionValidator),
    requiresApprover: v.boolean(),
    approver: v.optional(v.string()),
    tokenHash: v.optional(v.string()),
    tokenExpiresAt: v.optional(v.number()),
    status: v.optional(ProposalStatusValidator),
  },
  handler: async (ctx, args) => {
    // Verify event ownership
    const event = await ctx.db.get(args.eventId);
    if (!event || event.clerkUserId !== args.clerkUserId) {
      throw new Error("Event not found or access denied");
    }

    const now = Date.now();

    const proposalId = await ctx.db.insert("rescheduleProposals", {
      clerkUserId: args.clerkUserId,
      eventId: args.eventId,
      createdBy: args.createdBy,
      status: args.status ?? "pending",
      rationale: args.rationale,
      options: args.options,
      requiresApprover: args.requiresApprover,
      approver: args.approver,
      tokenHash: args.tokenHash,
      tokenExpiresAt: args.tokenExpiresAt,
      createdAt: now,
      updatedAt: now,
    });

    return await ctx.db.get(proposalId);
  },
});

/**
 * Record an approval decision on a proposal
 *
 * @param proposalId - The proposal ID
 * @param actor - Who made the decision
 * @param decision - The decision (approved/rejected/alternate)
 * @param chosenOptionIndex - Index of chosen option (for approved)
 * @param comment - Optional comment
 * @param alternate - Alternate time slot (for alternate decision)
 * @returns The created approval and updated proposal
 */
export const recordApproval = mutation({
  args: {
    proposalId: v.id("rescheduleProposals"),
    actor: v.string(),
    decision: ApprovalDecisionValidator,
    chosenOptionIndex: v.optional(v.number()),
    comment: v.optional(v.string()),
    alternate: v.optional(
      v.object({
        startAt: v.number(),
        endAt: v.number(),
      })
    ),
  },
  handler: async (ctx, args) => {
    const proposal = await ctx.db.get(args.proposalId);
    if (!proposal) {
      throw new Error("Proposal not found");
    }

    // Check if proposal is still pending
    if (proposal.status !== "pending") {
      throw new Error(`Proposal is already ${proposal.status}`);
    }

    // Check token expiration if applicable
    if (proposal.tokenExpiresAt && proposal.tokenExpiresAt < Date.now()) {
      await ctx.db.patch(args.proposalId, {
        status: "expired",
        updatedAt: Date.now(),
      });
      throw new Error("Approval token has expired");
    }

    const now = Date.now();

    // Record the approval
    const approvalId = await ctx.db.insert("approvals", {
      proposalId: args.proposalId,
      actor: args.actor,
      decision: args.decision,
      chosenOptionIndex: args.chosenOptionIndex,
      alternate: args.alternate,
      comment: args.comment,
      createdAt: now,
    });

    // Update proposal status based on decision
    const newStatus =
      args.decision === "approved"
        ? "approved"
        : args.decision === "rejected"
          ? "rejected"
          : "pending"; // alternate keeps it pending for further review

    await ctx.db.patch(args.proposalId, {
      status: newStatus,
      chosenOptionIndex:
        args.decision === "approved" ? args.chosenOptionIndex : undefined,
      updatedAt: now,
    });

    return {
      approval: await ctx.db.get(approvalId),
      proposal: await ctx.db.get(args.proposalId),
    };
  },
});

/**
 * Apply an approved proposal to the event
 *
 * @param clerkUserId - The user's Clerk ID
 * @param proposalId - The proposal ID
 * @returns The updated event
 */
export const applyApprovedProposal = mutation({
  args: {
    clerkUserId: v.string(),
    proposalId: v.id("rescheduleProposals"),
  },
  handler: async (ctx, args) => {
    const proposal = await ctx.db.get(args.proposalId);
    if (!proposal || proposal.clerkUserId !== args.clerkUserId) {
      throw new Error("Proposal not found or access denied");
    }

    if (proposal.status !== "approved") {
      throw new Error("Proposal must be approved before applying");
    }

    if (proposal.chosenOptionIndex === undefined) {
      throw new Error("No option was chosen");
    }

    const chosenOption = proposal.options[proposal.chosenOptionIndex];
    if (!chosenOption) {
      throw new Error("Invalid chosen option index");
    }

    const now = Date.now();

    // Update the event with new times
    await ctx.db.patch(proposal.eventId, {
      startAt: chosenOption.startAt,
      endAt: chosenOption.endAt,
      updatedAt: now,
    });

    // Mark proposal as applied
    await ctx.db.patch(args.proposalId, {
      status: "applied",
      updatedAt: now,
    });

    return await ctx.db.get(proposal.eventId);
  },
});

/**
 * Update proposal status
 *
 * @param clerkUserId - The user's Clerk ID
 * @param proposalId - The proposal ID
 * @param status - The new status
 * @returns The updated proposal
 */
export const updateProposalStatus = mutation({
  args: {
    clerkUserId: v.string(),
    proposalId: v.id("rescheduleProposals"),
    status: ProposalStatusValidator,
  },
  handler: async (ctx, args) => {
    const proposal = await ctx.db.get(args.proposalId);
    if (!proposal || proposal.clerkUserId !== args.clerkUserId) {
      throw new Error("Proposal not found or access denied");
    }

    await ctx.db.patch(args.proposalId, {
      status: args.status,
      updatedAt: Date.now(),
    });

    return await ctx.db.get(args.proposalId);
  },
});

// ============================================================================
// Policy Mutations
// ============================================================================

/**
 * Update user's calendar policy
 *
 * @param clerkUserId - The user's Clerk ID
 * @param policyData - The policy data to update
 * @returns The updated policy
 */
export const updatePolicy = mutation({
  args: {
    clerkUserId: v.string(),
    workHours: v.optional(WorkHoursValidator),
    focusBlocks: v.optional(v.array(FocusBlockValidator)),
    meetingLimits: v.optional(MeetingLimitsValidator),
    autoApplyFlexible: v.optional(v.boolean()),
    autoSendApprovals: v.optional(v.boolean()),
    applyOnApproval: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const { clerkUserId, ...policyData } = args;
    const now = Date.now();

    // Check for existing policy
    const existing = await ctx.db
      .query("calendarPolicies")
      .withIndex("by_clerk_id", (q) => q.eq("clerkUserId", clerkUserId))
      .unique();

    if (existing) {
      // Update existing policy
      const updateData: Record<string, unknown> = { updatedAt: now };
      if (policyData.workHours !== undefined)
        updateData.workHours = policyData.workHours;
      if (policyData.focusBlocks !== undefined)
        updateData.focusBlocks = policyData.focusBlocks;
      if (policyData.meetingLimits !== undefined)
        updateData.meetingLimits = policyData.meetingLimits;
      if (policyData.autoApplyFlexible !== undefined)
        updateData.autoApplyFlexible = policyData.autoApplyFlexible;
      if (policyData.autoSendApprovals !== undefined)
        updateData.autoSendApprovals = policyData.autoSendApprovals;
      if (policyData.applyOnApproval !== undefined)
        updateData.applyOnApproval = policyData.applyOnApproval;

      await ctx.db.patch(existing._id, updateData);
      return await ctx.db.get(existing._id);
    } else {
      // Create new policy with defaults
      const policyId = await ctx.db.insert("calendarPolicies", {
        clerkUserId,
        workHours: policyData.workHours ?? {
          timezone: "America/New_York",
          days: [
            { day: 1, startHour: 9, startMinute: 0, endHour: 17, endMinute: 0 },
            { day: 2, startHour: 9, startMinute: 0, endHour: 17, endMinute: 0 },
            { day: 3, startHour: 9, startMinute: 0, endHour: 17, endMinute: 0 },
            { day: 4, startHour: 9, startMinute: 0, endHour: 17, endMinute: 0 },
            { day: 5, startHour: 9, startMinute: 0, endHour: 17, endMinute: 0 },
          ],
        },
        focusBlocks: policyData.focusBlocks ?? [],
        meetingLimits: policyData.meetingLimits ?? {},
        autoApplyFlexible: policyData.autoApplyFlexible ?? false,
        autoSendApprovals: policyData.autoSendApprovals ?? false,
        applyOnApproval: policyData.applyOnApproval ?? true,
        updatedAt: now,
      });
      return await ctx.db.get(policyId);
    }
  },
});

// ============================================================================
// Task Mutations
// ============================================================================

/**
 * Create a new task
 *
 * @param clerkUserId - The user's Clerk ID
 * @param taskData - The task data
 * @returns The created task
 */
export const createTask = mutation({
  args: {
    clerkUserId: v.string(),
    taskId: v.string(),
    title: v.string(),
    notes: v.optional(v.string()),
    durationMinutes: v.number(),
    dueAt: v.optional(v.number()),
    priority: TaskPriorityValidator,
    dependencies: v.optional(v.array(v.string())),
    chunkMinMinutes: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const now = Date.now();

    // Check if task with same taskId exists
    const existing = await ctx.db
      .query("calendarTasks")
      .withIndex("by_task_id", (q) =>
        q.eq("clerkUserId", args.clerkUserId).eq("taskId", args.taskId)
      )
      .unique();

    if (existing) {
      throw new Error("Task with this ID already exists");
    }

    const taskDocId = await ctx.db.insert("calendarTasks", {
      clerkUserId: args.clerkUserId,
      taskId: args.taskId,
      title: args.title,
      notes: args.notes,
      durationMinutes: args.durationMinutes,
      dueAt: args.dueAt,
      priority: args.priority,
      dependencies: args.dependencies ?? [],
      chunkMinMinutes: args.chunkMinMinutes,
      status: "pending",
      updatedAt: now,
    });

    return await ctx.db.get(taskDocId);
  },
});

/**
 * Update an existing task
 *
 * @param clerkUserId - The user's Clerk ID
 * @param taskId - The task ID
 * @param updates - The fields to update
 * @returns The updated task
 */
export const updateTask = mutation({
  args: {
    clerkUserId: v.string(),
    taskId: v.string(),
    title: v.optional(v.string()),
    notes: v.optional(v.string()),
    durationMinutes: v.optional(v.number()),
    dueAt: v.optional(v.number()),
    priority: v.optional(TaskPriorityValidator),
    dependencies: v.optional(v.array(v.string())),
    chunkMinMinutes: v.optional(v.number()),
    status: v.optional(TaskStatusValidator),
  },
  handler: async (ctx, args) => {
    const { clerkUserId, taskId, ...updates } = args;

    // Find the task
    const task = await ctx.db
      .query("calendarTasks")
      .withIndex("by_task_id", (q) =>
        q.eq("clerkUserId", clerkUserId).eq("taskId", taskId)
      )
      .unique();

    if (!task) {
      throw new Error("Task not found or access denied");
    }

    // Build update object
    const updateData: Record<string, unknown> = { updatedAt: Date.now() };
    if (updates.title !== undefined) updateData.title = updates.title;
    if (updates.notes !== undefined) updateData.notes = updates.notes;
    if (updates.durationMinutes !== undefined)
      updateData.durationMinutes = updates.durationMinutes;
    if (updates.dueAt !== undefined) updateData.dueAt = updates.dueAt;
    if (updates.priority !== undefined) updateData.priority = updates.priority;
    if (updates.dependencies !== undefined)
      updateData.dependencies = updates.dependencies;
    if (updates.chunkMinMinutes !== undefined)
      updateData.chunkMinMinutes = updates.chunkMinMinutes;
    if (updates.status !== undefined) updateData.status = updates.status;

    await ctx.db.patch(task._id, updateData);
    return await ctx.db.get(task._id);
  },
});

/**
 * Delete a task
 *
 * @param clerkUserId - The user's Clerk ID
 * @param taskId - The task ID
 * @returns Success status
 */
export const deleteTask = mutation({
  args: {
    clerkUserId: v.string(),
    taskId: v.string(),
  },
  handler: async (ctx, args) => {
    const task = await ctx.db
      .query("calendarTasks")
      .withIndex("by_task_id", (q) =>
        q.eq("clerkUserId", args.clerkUserId).eq("taskId", args.taskId)
      )
      .unique();

    if (!task) {
      throw new Error("Task not found or access denied");
    }

    const now = Date.now();

    // Create tombstone
    await ctx.db.insert("tombstones", {
      clerkUserId: args.clerkUserId,
      kind: "task",
      refId: task._id,
      reason: "user_deleted",
      createdAt: now,
    });

    // Hard delete the task
    await ctx.db.delete(task._id);

    return { success: true };
  },
});

// ============================================================================
// User Mutations
// ============================================================================

/**
 * Create or update user
 *
 * @param clerkUserId - The user's Clerk ID
 * @param email - The user's email
 * @param role - The user's role
 * @returns The user record
 */
export const upsertUser = mutation({
  args: {
    clerkUserId: v.string(),
    email: v.string(),
    role: v.optional(v.union(v.literal("user"), v.literal("admin"))),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("users")
      .withIndex("by_clerk_id", (q) => q.eq("clerkUserId", args.clerkUserId))
      .unique();

    if (existing) {
      await ctx.db.patch(existing._id, {
        email: args.email,
        role: args.role ?? existing.role,
      });
      return await ctx.db.get(existing._id);
    }

    const userId = await ctx.db.insert("users", {
      clerkUserId: args.clerkUserId,
      email: args.email,
      role: args.role ?? "user",
      createdAt: Date.now(),
    });

    return await ctx.db.get(userId);
  },
});

/**
 * Update user consent
 *
 * @param clerkUserId - The user's Clerk ID
 * @param version - The consent version
 * @param scopes - Array of consent scopes
 * @returns The consent record
 */
export const updateUserConsent = mutation({
  args: {
    clerkUserId: v.string(),
    version: v.string(),
    scopes: v.array(v.string()),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("userConsents")
      .withIndex("by_clerk_id", (q) => q.eq("clerkUserId", args.clerkUserId))
      .unique();

    const now = Date.now();

    if (existing) {
      await ctx.db.patch(existing._id, {
        version: args.version,
        scopes: args.scopes,
        updatedAt: now,
      });
      return await ctx.db.get(existing._id);
    }

    const consentId = await ctx.db.insert("userConsents", {
      clerkUserId: args.clerkUserId,
      version: args.version,
      scopes: args.scopes,
      updatedAt: now,
    });

    return await ctx.db.get(consentId);
  },
});

// ============================================================================
// Account Mutations
// ============================================================================

/**
 * Create or update calendar account
 *
 * @param clerkUserId - The user's Clerk ID
 * @param provider - The calendar provider
 * @param primaryEmail - The primary email for this account
 * @param status - The account status
 * @returns The account record
 */
export const upsertCalendarAccount = mutation({
  args: {
    clerkUserId: v.string(),
    provider: v.union(
      v.literal("google"),
      v.literal("outlook"),
      v.literal("apple"),
      v.literal("caldav")
    ),
    primaryEmail: v.string(),
    status: v.union(
      v.literal("active"),
      v.literal("disconnected"),
      v.literal("error"),
      v.literal("pending")
    ),
  },
  handler: async (ctx, args) => {
    // Check for existing account with same provider
    const existing = await ctx.db
      .query("calendarAccounts")
      .withIndex("by_clerk_id_provider", (q) =>
        q.eq("clerkUserId", args.clerkUserId).eq("provider", args.provider)
      )
      .unique();

    const now = Date.now();

    if (existing) {
      await ctx.db.patch(existing._id, {
        primaryEmail: args.primaryEmail,
        status: args.status,
      });
      return { account: await ctx.db.get(existing._id), isNew: false };
    }

    const accountId = await ctx.db.insert("calendarAccounts", {
      clerkUserId: args.clerkUserId,
      provider: args.provider,
      primaryEmail: args.primaryEmail,
      status: args.status,
      createdAt: now,
    });

    return { account: await ctx.db.get(accountId), isNew: true };
  },
});

/**
 * Disconnect calendar account
 *
 * @param clerkUserId - The user's Clerk ID
 * @param accountId - The account ID
 * @returns Success status
 */
export const disconnectCalendarAccount = mutation({
  args: {
    clerkUserId: v.string(),
    accountId: v.id("calendarAccounts"),
  },
  handler: async (ctx, args) => {
    const account = await ctx.db.get(args.accountId);
    if (!account || account.clerkUserId !== args.clerkUserId) {
      throw new Error("Account not found or access denied");
    }

    await ctx.db.patch(args.accountId, {
      status: "disconnected",
    });

    // Create tombstone
    await ctx.db.insert("tombstones", {
      clerkUserId: args.clerkUserId,
      kind: "account",
      refId: args.accountId,
      reason: "user_disconnected",
      createdAt: Date.now(),
    });

    return { success: true };
  },
});

// ============================================================================
// Internal Mutations (for system use)
// ============================================================================

/**
 * Expire old proposals (called by scheduler)
 */
export const expireOldProposals = internalMutation({
  args: {},
  handler: async (ctx) => {
    const now = Date.now();

    // Find pending proposals with expired tokens
    const expiredProposals = await ctx.db
      .query("rescheduleProposals")
      .withIndex("by_clerk_id_status")
      .filter((q) =>
        q.and(
          q.eq(q.field("status"), "pending"),
          q.lt(q.field("tokenExpiresAt"), now)
        )
      )
      .take(100);

    let expiredCount = 0;
    for (const proposal of expiredProposals) {
      await ctx.db.patch(proposal._id, {
        status: "expired",
        updatedAt: now,
      });
      expiredCount++;
    }

    return { expiredCount };
  },
});
