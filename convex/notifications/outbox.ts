/**
 * Notification Outbox
 *
 * This module provides functions for managing the notification queue.
 * Notifications are queued here and processed asynchronously by workers.
 *
 * Supported Channels:
 * - email: Send via email service
 * - push: Send via push notification service
 * - sms: Send via SMS service
 * - in_app: Show in-app notification
 *
 * Queue Model:
 * - Notifications start in "pending" status
 * - Workers claim and process notifications
 * - Status transitions: pending -> sent/failed
 * - Failed notifications can be retried
 */

import { mutation, query, internalMutation } from "../_generated/server";
import { v } from "convex/values";
import { Id } from "../_generated/dataModel";
import { NotificationChannelValidator } from "../calendar/models";

// ============================================================================
// Public Mutations
// ============================================================================

/**
 * Enqueue a notification for sending
 *
 * @param clerkUserId - The user's Clerk ID
 * @param channel - The notification channel (email, push, sms, in_app)
 * @param to - The recipient address (email, phone, device token, etc.)
 * @param templateId - The notification template ID
 * @param payload - The template data/context
 * @returns The created notification record
 */
export const enqueueNotification = mutation({
  args: {
    clerkUserId: v.string(),
    channel: NotificationChannelValidator,
    to: v.string(),
    templateId: v.string(),
    payload: v.any(),
  },
  handler: async (ctx, args) => {
    const now = Date.now();

    const notificationId = await ctx.db.insert("notificationsOutbox", {
      clerkUserId: args.clerkUserId,
      channel: args.channel,
      to: args.to,
      templateId: args.templateId,
      payload: args.payload,
      status: "pending",
      attempts: 0,
      createdAt: now,
      updatedAt: now,
    });

    return await ctx.db.get(notificationId);
  },
});

/**
 * Enqueue multiple notifications in batch
 *
 * @param notifications - Array of notifications to enqueue
 * @returns Count of enqueued notifications
 */
export const enqueueNotificationsBatch = mutation({
  args: {
    notifications: v.array(
      v.object({
        clerkUserId: v.string(),
        channel: NotificationChannelValidator,
        to: v.string(),
        templateId: v.string(),
        payload: v.any(),
      })
    ),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    const ids: Id<"notificationsOutbox">[] = [];

    for (const notification of args.notifications) {
      const id = await ctx.db.insert("notificationsOutbox", {
        clerkUserId: notification.clerkUserId,
        channel: notification.channel,
        to: notification.to,
        templateId: notification.templateId,
        payload: notification.payload,
        status: "pending",
        attempts: 0,
        createdAt: now,
        updatedAt: now,
      });
      ids.push(id);
    }

    return { enqueuedCount: ids.length, ids };
  },
});

/**
 * Cancel a pending notification
 *
 * @param clerkUserId - The user's Clerk ID
 * @param notificationId - The notification ID
 * @returns Success status
 */
export const cancelNotification = mutation({
  args: {
    clerkUserId: v.string(),
    notificationId: v.id("notificationsOutbox"),
  },
  handler: async (ctx, args) => {
    const notification = await ctx.db.get(args.notificationId);

    if (!notification || notification.clerkUserId !== args.clerkUserId) {
      throw new Error("Notification not found or access denied");
    }

    if (notification.status !== "pending") {
      throw new Error("Can only cancel pending notifications");
    }

    await ctx.db.patch(args.notificationId, {
      status: "cancelled",
      updatedAt: Date.now(),
    });

    return { success: true };
  },
});

// ============================================================================
// Public Queries
// ============================================================================

/**
 * List pending notifications (for worker polling)
 *
 * @param limit - Maximum number of notifications to return
 * @returns Array of pending notifications
 */
export const listPendingOutbox = query({
  args: {
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const limit = args.limit ?? 50;

    return await ctx.db
      .query("notificationsOutbox")
      .withIndex("by_status", (q) => q.eq("status", "pending"))
      .order("asc")
      .take(limit);
  },
});

/**
 * List notifications for a user
 *
 * @param clerkUserId - The user's Clerk ID
 * @param status - Optional status filter
 * @param limit - Maximum number to return
 * @returns Array of notifications
 */
export const listUserNotifications = query({
  args: {
    clerkUserId: v.string(),
    status: v.optional(
      v.union(
        v.literal("pending"),
        v.literal("sent"),
        v.literal("failed"),
        v.literal("cancelled")
      )
    ),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const limit = args.limit ?? 50;

    let queryBuilder = ctx.db
      .query("notificationsOutbox")
      .withIndex("by_clerk_id", (q) => q.eq("clerkUserId", args.clerkUserId));

    if (args.status) {
      queryBuilder = queryBuilder.filter((q) =>
        q.eq(q.field("status"), args.status)
      );
    }

    return await queryBuilder.order("desc").take(limit);
  },
});

/**
 * Get notification by ID
 *
 * @param clerkUserId - The user's Clerk ID
 * @param notificationId - The notification ID
 * @returns The notification if found
 */
export const getNotification = query({
  args: {
    clerkUserId: v.string(),
    notificationId: v.id("notificationsOutbox"),
  },
  handler: async (ctx, args) => {
    const notification = await ctx.db.get(args.notificationId);

    if (!notification || notification.clerkUserId !== args.clerkUserId) {
      return null;
    }

    return notification;
  },
});

// ============================================================================
// Worker Mutations (for notification processing)
// ============================================================================

/**
 * Mark a notification as sent
 *
 * @param id - The notification ID
 * @returns Success status
 */
export const markOutboxSent = mutation({
  args: {
    id: v.id("notificationsOutbox"),
  },
  handler: async (ctx, args) => {
    const notification = await ctx.db.get(args.id);

    if (!notification) {
      throw new Error("Notification not found");
    }

    await ctx.db.patch(args.id, {
      status: "sent",
      updatedAt: Date.now(),
    });

    return { success: true };
  },
});

/**
 * Mark a notification as failed
 *
 * @param id - The notification ID
 * @param error - The error message
 * @returns Success status and current attempt count
 */
export const markOutboxFailed = mutation({
  args: {
    id: v.id("notificationsOutbox"),
    error: v.string(),
  },
  handler: async (ctx, args) => {
    const notification = await ctx.db.get(args.id);

    if (!notification) {
      throw new Error("Notification not found");
    }

    const now = Date.now();
    const newAttempts = notification.attempts + 1;

    // Mark as failed after 3 attempts
    const newStatus = newAttempts >= 3 ? "failed" : "pending";

    await ctx.db.patch(args.id, {
      status: newStatus,
      attempts: newAttempts,
      lastError: args.error,
      updatedAt: now,
    });

    return { success: true, attempts: newAttempts, finalStatus: newStatus };
  },
});

/**
 * Claim notifications for processing (prevents double-processing)
 *
 * @param limit - Maximum number to claim
 * @returns Array of claimed notification IDs
 */
export const claimNotificationsForProcessing = mutation({
  args: {
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const limit = args.limit ?? 10;

    // Find pending notifications with less than 3 attempts
    const pending = await ctx.db
      .query("notificationsOutbox")
      .withIndex("by_status_attempts", (q) => q.eq("status", "pending"))
      .filter((q) => q.lt(q.field("attempts"), 3))
      .take(limit);

    const now = Date.now();
    const claimedIds: Id<"notificationsOutbox">[] = [];

    for (const notification of pending) {
      // Increment attempts to "claim" the notification
      await ctx.db.patch(notification._id, {
        attempts: notification.attempts + 1,
        updatedAt: now,
      });
      claimedIds.push(notification._id);
    }

    return { claimedIds, claimedCount: claimedIds.length };
  },
});

// ============================================================================
// Internal Mutations (for system use)
// ============================================================================

/**
 * Clean up old sent/cancelled notifications
 * Called by scheduler to prevent unbounded growth
 */
export const cleanupOldNotifications = internalMutation({
  args: {
    /** Delete notifications older than this many days */
    olderThanDays: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const days = args.olderThanDays ?? 30;
    const cutoff = Date.now() - days * 24 * 60 * 60 * 1000;

    // Find old sent/cancelled notifications
    const oldNotifications = await ctx.db
      .query("notificationsOutbox")
      .filter((q) =>
        q.and(
          q.or(
            q.eq(q.field("status"), "sent"),
            q.eq(q.field("status"), "cancelled")
          ),
          q.lt(q.field("createdAt"), cutoff)
        )
      )
      .take(100);

    let deletedCount = 0;
    for (const notification of oldNotifications) {
      await ctx.db.delete(notification._id);
      deletedCount++;
    }

    return { deletedCount };
  },
});

/**
 * Retry failed notifications
 * Resets status to pending for another attempt
 */
export const retryFailedNotifications = internalMutation({
  args: {
    /** Maximum number to retry */
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const limit = args.limit ?? 50;

    const failed = await ctx.db
      .query("notificationsOutbox")
      .withIndex("by_status", (q) => q.eq("status", "failed"))
      .take(limit);

    const now = Date.now();
    let retriedCount = 0;

    for (const notification of failed) {
      await ctx.db.patch(notification._id, {
        status: "pending",
        attempts: 0,
        lastError: undefined,
        updatedAt: now,
      });
      retriedCount++;
    }

    return { retriedCount };
  },
});

/**
 * Get notification statistics
 */
export const getNotificationStats = query({
  args: {},
  handler: async (ctx) => {
    const pending = await ctx.db
      .query("notificationsOutbox")
      .withIndex("by_status", (q) => q.eq("status", "pending"))
      .collect();

    const sent = await ctx.db
      .query("notificationsOutbox")
      .withIndex("by_status", (q) => q.eq("status", "sent"))
      .collect();

    const failed = await ctx.db
      .query("notificationsOutbox")
      .withIndex("by_status", (q) => q.eq("status", "failed"))
      .collect();

    return {
      pending: pending.length,
      sent: sent.length,
      failed: failed.length,
    };
  },
});
