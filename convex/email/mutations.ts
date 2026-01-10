/**
 * Convex Mutations for Email Actions
 *
 * All mutations enforce user-level data isolation via userId.
 * Mutations are designed to be idempotent where possible using idempotency keys.
 *
 * Privacy/Consent Model:
 * - Only the authenticated user can modify their own data
 * - All actions are logged as events for audit and Brain processing
 * - Deletions create tombstones for sync compliance
 */

import { mutation, internalMutation } from "../_generated/server";
import { v } from "convex/values";
import { Id } from "../_generated/dataModel";
import type { EmailActionType } from "./types";

// ============================================================================
// Constants
// ============================================================================

const IDEMPOTENCY_KEY_TTL = 24 * 60 * 60 * 1000; // 24 hours in milliseconds

// ============================================================================
// Helper: Idempotency Check
// ============================================================================

/**
 * Check if an idempotency key has been used
 * Returns the cached result if found, null otherwise
 */
async function checkIdempotency(
  ctx: any,
  userId: string,
  key: string | undefined
): Promise<any | null> {
  if (!key) return null;

  const existing = await ctx.db
    .query("idempotencyKeys")
    .withIndex("by_key", (q: any) => q.eq("userId", userId).eq("key", key))
    .unique();

  if (existing && existing.expiresAt > Date.now()) {
    return existing.result;
  }

  return null;
}

/**
 * Store an idempotency key with its result
 */
async function storeIdempotency(
  ctx: any,
  userId: string,
  key: string,
  result: any
): Promise<void> {
  const now = Date.now();
  await ctx.db.insert("idempotencyKeys", {
    key,
    userId,
    result,
    createdAt: now,
    expiresAt: now + IDEMPOTENCY_KEY_TTL,
  });
}

// ============================================================================
// Thread Action Mutations
// ============================================================================

/**
 * Apply an action to one or more email threads
 * Actions: archive, unarchive, trash, untrash, delete, star, unstar, markRead, markUnread, addLabel, removeLabel
 *
 * This mutation is idempotent when an idempotencyKey is provided.
 */
export const applyAction = mutation({
  args: {
    userId: v.string(),
    accountId: v.id("emailAccounts"),
    threadIds: v.array(v.string()),
    action: v.union(
      v.literal("archive"),
      v.literal("unarchive"),
      v.literal("trash"),
      v.literal("untrash"),
      v.literal("delete"),
      v.literal("star"),
      v.literal("unstar"),
      v.literal("markRead"),
      v.literal("markUnread"),
      v.literal("addLabel"),
      v.literal("removeLabel"),
      v.literal("spam"),
      v.literal("notSpam"),
      v.literal("moveToInbox")
    ),
    labelId: v.optional(v.string()),
    idempotencyKey: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    // Check idempotency
    const cachedResult = await checkIdempotency(ctx, args.userId, args.idempotencyKey);
    if (cachedResult !== null) {
      return cachedResult;
    }

    const now = Date.now();
    let affectedCount = 0;
    const errors: Array<{ threadId: string; error: string }> = [];

    for (const threadId of args.threadIds) {
      // Get the thread
      const thread = await ctx.db
        .query("emailThreads")
        .withIndex("by_account_threadId", (q) =>
          q
            .eq("userId", args.userId)
            .eq("accountId", args.accountId)
            .eq("threadId", threadId)
        )
        .unique();

      if (!thread) {
        errors.push({ threadId, error: "Thread not found" });
        continue;
      }

      try {
        switch (args.action) {
          case "archive":
            // Remove from INBOX, add ARCHIVE label
            await ctx.db.patch(thread._id, {
              labels: thread.labels.filter((l) => l !== "INBOX").concat(
                thread.labels.includes("ARCHIVE") ? [] : ["ARCHIVE"]
              ),
              updatedAt: now,
            });
            break;

          case "unarchive":
            // Add to INBOX, remove ARCHIVE label
            await ctx.db.patch(thread._id, {
              labels: thread.labels.filter((l) => l !== "ARCHIVE").concat(
                thread.labels.includes("INBOX") ? [] : ["INBOX"]
              ),
              updatedAt: now,
            });
            break;

          case "trash":
            // Add TRASH label, remove from other folders
            await ctx.db.patch(thread._id, {
              labels: ["TRASH"],
              updatedAt: now,
            });
            break;

          case "untrash":
            // Remove TRASH label, add to INBOX
            await ctx.db.patch(thread._id, {
              labels: thread.labels.filter((l) => l !== "TRASH").concat(
                thread.labels.includes("INBOX") ? [] : ["INBOX"]
              ),
              updatedAt: now,
            });
            break;

          case "delete":
            // Permanent delete - create tombstone and remove
            await ctx.db.insert("emailTombstones", {
              userId: args.userId,
              entityType: "thread",
              entityId: threadId,
              deletedAt: now,
            });
            // Delete all messages in the thread
            const messages = await ctx.db
              .query("emailMessages")
              .withIndex("by_thread", (q) =>
                q
                  .eq("userId", args.userId)
                  .eq("accountId", args.accountId)
                  .eq("threadId", threadId)
              )
              .collect();
            for (const msg of messages) {
              await ctx.db.delete(msg._id);
            }
            await ctx.db.delete(thread._id);
            break;

          case "star":
            await ctx.db.patch(thread._id, {
              isStarred: true,
              updatedAt: now,
            });
            // Also star messages in the thread
            const msgsToStar = await ctx.db
              .query("emailMessages")
              .withIndex("by_thread", (q) =>
                q
                  .eq("userId", args.userId)
                  .eq("accountId", args.accountId)
                  .eq("threadId", threadId)
              )
              .collect();
            for (const msg of msgsToStar) {
              await ctx.db.patch(msg._id, { isStarred: true });
            }
            break;

          case "unstar":
            await ctx.db.patch(thread._id, {
              isStarred: false,
              updatedAt: now,
            });
            // Also unstar messages in the thread
            const msgsToUnstar = await ctx.db
              .query("emailMessages")
              .withIndex("by_thread", (q) =>
                q
                  .eq("userId", args.userId)
                  .eq("accountId", args.accountId)
                  .eq("threadId", threadId)
              )
              .collect();
            for (const msg of msgsToUnstar) {
              await ctx.db.patch(msg._id, { isStarred: false });
            }
            break;

          case "markRead":
            await ctx.db.patch(thread._id, {
              unreadCount: 0,
              updatedAt: now,
            });
            // Also mark all messages as read
            const msgsToMarkRead = await ctx.db
              .query("emailMessages")
              .withIndex("by_thread", (q) =>
                q
                  .eq("userId", args.userId)
                  .eq("accountId", args.accountId)
                  .eq("threadId", threadId)
              )
              .collect();
            for (const msg of msgsToMarkRead) {
              await ctx.db.patch(msg._id, { isRead: true });
            }
            break;

          case "markUnread":
            await ctx.db.patch(thread._id, {
              unreadCount: 1, // At least 1 unread
              updatedAt: now,
            });
            break;

          case "addLabel":
            if (!args.labelId) {
              errors.push({ threadId, error: "labelId required for addLabel" });
              continue;
            }
            if (!thread.labels.includes(args.labelId)) {
              await ctx.db.patch(thread._id, {
                labels: [...thread.labels, args.labelId],
                updatedAt: now,
              });
            }
            break;

          case "removeLabel":
            if (!args.labelId) {
              errors.push({ threadId, error: "labelId required for removeLabel" });
              continue;
            }
            await ctx.db.patch(thread._id, {
              labels: thread.labels.filter((l) => l !== args.labelId),
              updatedAt: now,
            });
            break;

          case "spam":
            await ctx.db.patch(thread._id, {
              labels: ["SPAM"],
              updatedAt: now,
            });
            break;

          case "notSpam":
            await ctx.db.patch(thread._id, {
              labels: thread.labels.filter((l) => l !== "SPAM").concat(
                thread.labels.includes("INBOX") ? [] : ["INBOX"]
              ),
              updatedAt: now,
            });
            break;

          case "moveToInbox":
            await ctx.db.patch(thread._id, {
              labels: thread.labels
                .filter((l) => !["ARCHIVE", "TRASH", "SPAM"].includes(l))
                .concat(thread.labels.includes("INBOX") ? [] : ["INBOX"]),
              updatedAt: now,
            });
            break;
        }

        affectedCount++;

        // Append event for Brain processing
        await ctx.db.insert("events", {
          userId: args.userId,
          type: "email.action.applied",
          payload: {
            accountId: args.accountId,
            threadId,
            action: args.action,
            labelId: args.labelId,
          },
          timestamp: now,
          brainStatus: "pending",
          idempotencyKey: args.idempotencyKey
            ? `${args.idempotencyKey}_${threadId}`
            : undefined,
        });
      } catch (error) {
        errors.push({
          threadId,
          error: error instanceof Error ? error.message : "Unknown error",
        });
      }
    }

    const result = {
      success: errors.length === 0,
      affectedCount,
      errors: errors.length > 0 ? errors : undefined,
    };

    // Store idempotency key
    if (args.idempotencyKey) {
      await storeIdempotency(ctx, args.userId, args.idempotencyKey, result);
    }

    return result;
  },
});

// ============================================================================
// Draft Mutations
// ============================================================================

/**
 * Create a new email draft
 */
export const createDraft = mutation({
  args: {
    userId: v.string(),
    accountId: v.id("emailAccounts"),
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
    body: v.string(),
    htmlBody: v.optional(v.string()),
    replyToMessageId: v.optional(v.string()),
    forwardFromMessageId: v.optional(v.string()),
    idempotencyKey: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    // Check idempotency
    const cachedResult = await checkIdempotency(ctx, args.userId, args.idempotencyKey);
    if (cachedResult !== null) {
      return cachedResult;
    }

    const now = Date.now();

    // Verify account ownership
    const account = await ctx.db.get(args.accountId);
    if (!account || account.userId !== args.userId) {
      throw new Error("Account not found or access denied");
    }

    // Create the draft
    const draftId = await ctx.db.insert("emailDrafts", {
      userId: args.userId,
      accountId: args.accountId,
      to: args.to,
      cc: args.cc ?? [],
      bcc: args.bcc ?? [],
      subject: args.subject,
      body: args.body,
      htmlBody: args.htmlBody,
      attachments: [],
      replyToMessageId: args.replyToMessageId,
      forwardFromMessageId: args.forwardFromMessageId,
      createdAt: now,
      updatedAt: now,
    });

    // Append event
    await ctx.db.insert("events", {
      userId: args.userId,
      type: "email.draft.created",
      payload: {
        accountId: args.accountId,
        draftId,
        subject: args.subject,
        recipientCount: args.to.length,
      },
      timestamp: now,
      brainStatus: "skipped", // Drafts don't need brain processing
    });

    const result = { draftId };

    // Store idempotency key
    if (args.idempotencyKey) {
      await storeIdempotency(ctx, args.userId, args.idempotencyKey, result);
    }

    return result;
  },
});

/**
 * Update an existing draft
 */
export const updateDraft = mutation({
  args: {
    userId: v.string(),
    draftId: v.id("emailDrafts"),
    to: v.optional(
      v.array(
        v.object({
          email: v.string(),
          name: v.optional(v.string()),
        })
      )
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
    subject: v.optional(v.string()),
    body: v.optional(v.string()),
    htmlBody: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    // Get and verify draft ownership
    const draft = await ctx.db.get(args.draftId);
    if (!draft || draft.userId !== args.userId) {
      throw new Error("Draft not found or access denied");
    }

    const now = Date.now();
    const updates: Record<string, any> = { updatedAt: now };

    if (args.to !== undefined) updates.to = args.to;
    if (args.cc !== undefined) updates.cc = args.cc;
    if (args.bcc !== undefined) updates.bcc = args.bcc;
    if (args.subject !== undefined) updates.subject = args.subject;
    if (args.body !== undefined) updates.body = args.body;
    if (args.htmlBody !== undefined) updates.htmlBody = args.htmlBody;

    await ctx.db.patch(args.draftId, updates);

    // Append event
    await ctx.db.insert("events", {
      userId: args.userId,
      type: "email.draft.updated",
      payload: {
        draftId: args.draftId,
        updatedFields: Object.keys(updates).filter((k) => k !== "updatedAt"),
      },
      timestamp: now,
      brainStatus: "skipped",
    });

    return { success: true };
  },
});

/**
 * Delete a draft
 */
export const deleteDraft = mutation({
  args: {
    userId: v.string(),
    draftId: v.id("emailDrafts"),
  },
  handler: async (ctx, args) => {
    // Get and verify draft ownership
    const draft = await ctx.db.get(args.draftId);
    if (!draft || draft.userId !== args.userId) {
      throw new Error("Draft not found or access denied");
    }

    const now = Date.now();

    // Create tombstone
    await ctx.db.insert("emailTombstones", {
      userId: args.userId,
      entityType: "draft",
      entityId: args.draftId,
      deletedAt: now,
    });

    // Delete the draft
    await ctx.db.delete(args.draftId);

    // Append event
    await ctx.db.insert("events", {
      userId: args.userId,
      type: "email.draft.deleted",
      payload: {
        draftId: args.draftId,
      },
      timestamp: now,
      brainStatus: "skipped",
    });

    return { success: true };
  },
});

/**
 * Mark a draft as sent (for connector to pick up and actually send)
 * This creates an event that the connector will process
 */
export const sendDraft = mutation({
  args: {
    userId: v.string(),
    draftId: v.id("emailDrafts"),
    idempotencyKey: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    // Check idempotency
    const cachedResult = await checkIdempotency(ctx, args.userId, args.idempotencyKey);
    if (cachedResult !== null) {
      return cachedResult;
    }

    // Get and verify draft ownership
    const draft = await ctx.db.get(args.draftId);
    if (!draft || draft.userId !== args.userId) {
      throw new Error("Draft not found or access denied");
    }

    const now = Date.now();

    // Create send event for connector to process
    const eventId = await ctx.db.insert("events", {
      userId: args.userId,
      type: "email.message.sent",
      payload: {
        accountId: draft.accountId,
        draftId: args.draftId,
        to: draft.to,
        cc: draft.cc,
        bcc: draft.bcc,
        subject: draft.subject,
        body: draft.body,
        htmlBody: draft.htmlBody,
        replyToMessageId: draft.replyToMessageId,
        forwardFromMessageId: draft.forwardFromMessageId,
        status: "queued", // Connector will update to "sent" or "failed"
      },
      timestamp: now,
      brainStatus: "pending",
      idempotencyKey: args.idempotencyKey,
    });

    const result = {
      success: true,
      eventId,
      message: "Email queued for sending",
    };

    // Store idempotency key
    if (args.idempotencyKey) {
      await storeIdempotency(ctx, args.userId, args.idempotencyKey, result);
    }

    return result;
  },
});

// ============================================================================
// Label Mutations
// ============================================================================

/**
 * Create a user label
 */
export const addLabel = mutation({
  args: {
    userId: v.string(),
    accountId: v.id("emailAccounts"),
    name: v.string(),
    color: v.optional(v.string()),
    idempotencyKey: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    // Check idempotency
    const cachedResult = await checkIdempotency(ctx, args.userId, args.idempotencyKey);
    if (cachedResult !== null) {
      return cachedResult;
    }

    // Verify account ownership
    const account = await ctx.db.get(args.accountId);
    if (!account || account.userId !== args.userId) {
      throw new Error("Account not found or access denied");
    }

    const now = Date.now();

    // Generate a unique label ID
    const labelId = `user_${now}_${Math.random().toString(36).slice(2, 9)}`;

    // Create the label
    const id = await ctx.db.insert("emailLabels", {
      userId: args.userId,
      accountId: args.accountId,
      labelId,
      name: args.name,
      type: "user",
      color: args.color,
      messageCount: 0,
      unreadCount: 0,
    });

    // Append event
    await ctx.db.insert("events", {
      userId: args.userId,
      type: "email.label.created",
      payload: {
        accountId: args.accountId,
        labelId: id,
        name: args.name,
      },
      timestamp: now,
      brainStatus: "skipped",
    });

    const result = { labelId: id, providerLabelId: labelId };

    // Store idempotency key
    if (args.idempotencyKey) {
      await storeIdempotency(ctx, args.userId, args.idempotencyKey, result);
    }

    return result;
  },
});

/**
 * Delete a user label
 */
export const deleteLabel = mutation({
  args: {
    userId: v.string(),
    labelId: v.id("emailLabels"),
  },
  handler: async (ctx, args) => {
    // Get and verify label ownership
    const label = await ctx.db.get(args.labelId);
    if (!label || label.userId !== args.userId) {
      throw new Error("Label not found or access denied");
    }

    // Can't delete system labels
    if (label.type === "system") {
      throw new Error("Cannot delete system labels");
    }

    const now = Date.now();

    // Remove label from all threads
    const threads = await ctx.db
      .query("emailThreads")
      .withIndex("by_account_date", (q) =>
        q.eq("userId", args.userId).eq("accountId", label.accountId)
      )
      .collect();

    for (const thread of threads) {
      if (thread.labels.includes(label.labelId)) {
        await ctx.db.patch(thread._id, {
          labels: thread.labels.filter((l) => l !== label.labelId),
          updatedAt: now,
        });
      }
    }

    // Create tombstone
    await ctx.db.insert("emailTombstones", {
      userId: args.userId,
      entityType: "label",
      entityId: label.labelId,
      deletedAt: now,
    });

    // Delete the label
    await ctx.db.delete(args.labelId);

    // Append event
    await ctx.db.insert("events", {
      userId: args.userId,
      type: "email.label.deleted",
      payload: {
        labelId: args.labelId,
        name: label.name,
      },
      timestamp: now,
      brainStatus: "skipped",
    });

    return { success: true };
  },
});

// ============================================================================
// Sync State Mutations
// ============================================================================

/**
 * Update sync state after sync operation
 */
export const updateSyncState = mutation({
  args: {
    userId: v.string(),
    accountId: v.id("emailAccounts"),
    historyId: v.optional(v.string()),
    cursor: v.optional(v.string()),
    syncStatus: v.union(
      v.literal("idle"),
      v.literal("syncing"),
      v.literal("error")
    ),
    errorMessage: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    // Get existing sync state
    const existing = await ctx.db
      .query("emailSyncState")
      .withIndex("by_account", (q) =>
        q.eq("userId", args.userId).eq("accountId", args.accountId)
      )
      .unique();

    const now = Date.now();

    if (existing) {
      // Update existing
      await ctx.db.patch(existing._id, {
        historyId: args.historyId ?? existing.historyId,
        cursor: args.cursor ?? existing.cursor,
        syncStatus: args.syncStatus,
        errorMessage: args.errorMessage,
        lastSyncAt: args.syncStatus === "idle" ? now : existing.lastSyncAt,
      });
    } else {
      // Create new
      await ctx.db.insert("emailSyncState", {
        userId: args.userId,
        accountId: args.accountId,
        historyId: args.historyId,
        cursor: args.cursor,
        lastSyncAt: now,
        syncStatus: args.syncStatus,
        errorMessage: args.errorMessage,
      });
    }

    // Append sync completed event if transitioning to idle
    if (args.syncStatus === "idle") {
      await ctx.db.insert("events", {
        userId: args.userId,
        type: "email.sync.completed",
        payload: {
          accountId: args.accountId,
          historyId: args.historyId,
          cursor: args.cursor,
        },
        timestamp: now,
        brainStatus: "skipped",
      });
    }

    return { success: true };
  },
});

// ============================================================================
// Account Mutations
// ============================================================================

/**
 * Create or update an email account
 */
export const upsertAccount = mutation({
  args: {
    userId: v.string(),
    provider: v.union(v.literal("gmail"), v.literal("imap"), v.literal("outlook")),
    emailAddress: v.string(),
    accessTokenRef: v.optional(v.string()),
    refreshTokenRef: v.optional(v.string()),
    status: v.union(v.literal("active"), v.literal("disconnected"), v.literal("error")),
    errorMessage: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const now = Date.now();

    // Check for existing account
    const existing = await ctx.db
      .query("emailAccounts")
      .withIndex("by_user_email", (q) =>
        q.eq("userId", args.userId).eq("emailAddress", args.emailAddress)
      )
      .unique();

    if (existing) {
      // Update existing
      await ctx.db.patch(existing._id, {
        provider: args.provider,
        accessTokenRef: args.accessTokenRef,
        refreshTokenRef: args.refreshTokenRef,
        status: args.status,
        errorMessage: args.errorMessage,
        updatedAt: now,
      });

      return { accountId: existing._id, isNew: false };
    }

    // Create new account
    const accountId = await ctx.db.insert("emailAccounts", {
      userId: args.userId,
      provider: args.provider,
      emailAddress: args.emailAddress,
      accessTokenRef: args.accessTokenRef,
      refreshTokenRef: args.refreshTokenRef,
      status: args.status,
      errorMessage: args.errorMessage,
      createdAt: now,
      updatedAt: now,
    });

    // Create initial sync state
    await ctx.db.insert("emailSyncState", {
      userId: args.userId,
      accountId,
      lastSyncAt: 0,
      syncStatus: "idle",
    });

    // Append event
    await ctx.db.insert("events", {
      userId: args.userId,
      type: "email.account.connected",
      payload: {
        accountId,
        provider: args.provider,
        emailAddress: args.emailAddress,
      },
      timestamp: now,
      brainStatus: "skipped",
    });

    return { accountId, isNew: true };
  },
});

/**
 * Disconnect (soft delete) an email account
 */
export const disconnectAccount = mutation({
  args: {
    userId: v.string(),
    accountId: v.id("emailAccounts"),
  },
  handler: async (ctx, args) => {
    // Get and verify account ownership
    const account = await ctx.db.get(args.accountId);
    if (!account || account.userId !== args.userId) {
      throw new Error("Account not found or access denied");
    }

    const now = Date.now();

    // Update status to disconnected
    await ctx.db.patch(args.accountId, {
      status: "disconnected",
      accessTokenRef: undefined,
      refreshTokenRef: undefined,
      updatedAt: now,
    });

    // Append event
    await ctx.db.insert("events", {
      userId: args.userId,
      type: "email.account.disconnected",
      payload: {
        accountId: args.accountId,
        provider: account.provider,
        emailAddress: account.emailAddress,
      },
      timestamp: now,
      brainStatus: "skipped",
    });

    return { success: true };
  },
});

// ============================================================================
// Batch Insert (for Connector use)
// ============================================================================

/**
 * Batch insert messages from sync
 * Used by the email connector to insert messages during sync
 */
export const batchInsertMessages = mutation({
  args: {
    userId: v.string(),
    accountId: v.id("emailAccounts"),
    messages: v.array(
      v.object({
        messageId: v.string(),
        threadId: v.string(),
        from: v.object({
          email: v.string(),
          name: v.optional(v.string()),
        }),
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
        snippet: v.string(),
        bodyRef: v.optional(v.string()),
        htmlBodyRef: v.optional(v.string()),
        internalDate: v.number(),
        attachments: v.optional(
          v.array(
            v.object({
              id: v.string(),
              filename: v.string(),
              mimeType: v.string(),
              size: v.number(),
              contentRef: v.optional(v.string()),
              contentId: v.optional(v.string()),
              isInline: v.boolean(),
            })
          )
        ),
        labelIds: v.array(v.string()),
        headers: v.optional(v.any()),
        isRead: v.boolean(),
        isStarred: v.boolean(),
      })
    ),
    syncState: v.optional(
      v.object({
        historyId: v.optional(v.string()),
        cursor: v.optional(v.string()),
      })
    ),
  },
  handler: async (ctx, args) => {
    // Verify account ownership
    const account = await ctx.db.get(args.accountId);
    if (!account || account.userId !== args.userId) {
      throw new Error("Account not found or access denied");
    }

    const now = Date.now();
    let insertedCount = 0;
    let updatedThreads = 0;
    const threadUpdates = new Map<
      string,
      {
        lastMessageAt: number;
        snippet: string;
        subject: string;
        participants: Set<string>;
        hasAttachments: boolean;
        isStarred: boolean;
        unreadCount: number;
        labels: Set<string>;
      }
    >();

    for (const msg of args.messages) {
      // Check if message already exists (idempotent)
      const existing = await ctx.db
        .query("emailMessages")
        .withIndex("by_account_messageId", (q) =>
          q
            .eq("userId", args.userId)
            .eq("accountId", args.accountId)
            .eq("messageId", msg.messageId)
        )
        .unique();

      if (!existing) {
        // Insert the message
        await ctx.db.insert("emailMessages", {
          userId: args.userId,
          accountId: args.accountId,
          messageId: msg.messageId,
          threadId: msg.threadId,
          from: msg.from,
          to: msg.to,
          cc: msg.cc ?? [],
          bcc: msg.bcc ?? [],
          subject: msg.subject,
          snippet: msg.snippet,
          bodyRef: msg.bodyRef,
          htmlBodyRef: msg.htmlBodyRef,
          internalDate: msg.internalDate,
          attachments: msg.attachments ?? [],
          labelIds: msg.labelIds,
          headers: msg.headers,
          isRead: msg.isRead,
          isStarred: msg.isStarred,
        });

        insertedCount++;

        // Append event for Brain processing
        await ctx.db.insert("events", {
          userId: args.userId,
          type: "email.message.received",
          payload: {
            accountId: args.accountId,
            messageId: msg.messageId,
            threadId: msg.threadId,
            from: msg.from,
            subject: msg.subject,
            hasAttachments: (msg.attachments?.length ?? 0) > 0,
          },
          timestamp: now,
          brainStatus: "pending",
        });
      }

      // Track thread updates
      const threadUpdate = threadUpdates.get(msg.threadId) ?? {
        lastMessageAt: 0,
        snippet: "",
        subject: msg.subject,
        participants: new Set<string>(),
        hasAttachments: false,
        isStarred: false,
        unreadCount: 0,
        labels: new Set<string>(),
      };

      if (msg.internalDate > threadUpdate.lastMessageAt) {
        threadUpdate.lastMessageAt = msg.internalDate;
        threadUpdate.snippet = msg.snippet;
      }

      threadUpdate.participants.add(msg.from.email);
      msg.to.forEach((r) => threadUpdate.participants.add(r.email));
      if (msg.attachments && msg.attachments.length > 0) {
        threadUpdate.hasAttachments = true;
      }
      if (msg.isStarred) threadUpdate.isStarred = true;
      if (!msg.isRead) threadUpdate.unreadCount++;
      msg.labelIds.forEach((l) => threadUpdate.labels.add(l));

      threadUpdates.set(msg.threadId, threadUpdate);
    }

    // Update or create threads
    for (const [threadId, update] of threadUpdates) {
      const existingThread = await ctx.db
        .query("emailThreads")
        .withIndex("by_account_threadId", (q) =>
          q
            .eq("userId", args.userId)
            .eq("accountId", args.accountId)
            .eq("threadId", threadId)
        )
        .unique();

      const participants = Array.from(update.participants).map((email) => ({
        email,
        name: undefined,
      }));

      if (existingThread) {
        // Update existing thread
        await ctx.db.patch(existingThread._id, {
          lastMessageAt: Math.max(existingThread.lastMessageAt, update.lastMessageAt),
          snippet: update.lastMessageAt > existingThread.lastMessageAt
            ? update.snippet
            : existingThread.snippet,
          hasAttachments: existingThread.hasAttachments || update.hasAttachments,
          isStarred: existingThread.isStarred || update.isStarred,
          unreadCount: existingThread.unreadCount + update.unreadCount,
          labels: Array.from(
            new Set([...existingThread.labels, ...Array.from(update.labels)])
          ),
          updatedAt: now,
        });
      } else {
        // Create new thread
        await ctx.db.insert("emailThreads", {
          userId: args.userId,
          accountId: args.accountId,
          threadId,
          snippet: update.snippet,
          subject: update.subject,
          lastMessageAt: update.lastMessageAt,
          unreadCount: update.unreadCount,
          labels: Array.from(update.labels),
          participants,
          hasAttachments: update.hasAttachments,
          isStarred: update.isStarred,
          updatedAt: now,
        });
      }

      updatedThreads++;
    }

    // Update sync state if provided
    if (args.syncState) {
      const existingSyncState = await ctx.db
        .query("emailSyncState")
        .withIndex("by_account", (q) =>
          q.eq("userId", args.userId).eq("accountId", args.accountId)
        )
        .unique();

      if (existingSyncState) {
        await ctx.db.patch(existingSyncState._id, {
          historyId: args.syncState.historyId ?? existingSyncState.historyId,
          cursor: args.syncState.cursor ?? existingSyncState.cursor,
          lastSyncAt: now,
        });
      }
    }

    return {
      success: true,
      insertedCount,
      updatedThreads,
    };
  },
});

// ============================================================================
// Internal Mutations (for scheduled jobs)
// ============================================================================

/**
 * Clean up expired idempotency keys
 */
export const cleanupIdempotencyKeys = internalMutation({
  handler: async (ctx) => {
    const now = Date.now();
    const expired = await ctx.db
      .query("idempotencyKeys")
      .withIndex("by_expires", (q) => q.lt("expiresAt", now))
      .take(100);

    for (const key of expired) {
      await ctx.db.delete(key._id);
    }

    return { deletedCount: expired.length };
  },
});

/**
 * Clean up old tombstones (keep for 30 days)
 */
export const cleanupTombstones = internalMutation({
  handler: async (ctx) => {
    const thirtyDaysAgo = Date.now() - 30 * 24 * 60 * 60 * 1000;
    const old = await ctx.db
      .query("emailTombstones")
      .withIndex("by_deleted", (q) => q.lt("deletedAt", thirtyDaysAgo))
      .take(100);

    for (const tombstone of old) {
      await ctx.db.delete(tombstone._id);
    }

    return { deletedCount: old.length };
  },
});
