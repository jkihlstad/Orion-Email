/**
 * Convex Queries for Email Data
 *
 * All queries enforce user-level data isolation via userId.
 * No cross-user data access is permitted.
 *
 * These queries are designed for:
 * - Cursor-based pagination (efficient for infinite scroll)
 * - Filtering by labels
 * - Basic search functionality
 */

import { query } from "../_generated/server";
import { v } from "convex/values";
import { Doc, Id } from "../_generated/dataModel";

// ============================================================================
// Constants
// ============================================================================

const DEFAULT_PAGE_SIZE = 50;
const MAX_PAGE_SIZE = 100;

// ============================================================================
// Thread Queries
// ============================================================================

/**
 * List email threads with pagination, optional label filter, and basic search
 *
 * Pagination is cursor-based using the lastMessageAt timestamp.
 * Results are sorted by lastMessageAt descending (newest first).
 */
export const listThreads = query({
  args: {
    userId: v.string(),
    accountId: v.id("emailAccounts"),
    /** Filter by label ID (optional) */
    labelId: v.optional(v.string()),
    /** Basic search query (searches subject and snippet) */
    query: v.optional(v.string()),
    /** Pagination cursor (lastMessageAt timestamp) */
    cursor: v.optional(v.number()),
    /** Number of items to return (default 50, max 100) */
    limit: v.optional(v.number()),
    /** Filter starred only */
    starredOnly: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const limit = Math.min(args.limit ?? DEFAULT_PAGE_SIZE, MAX_PAGE_SIZE);

    // Build the query based on filters
    let threadsQuery;

    if (args.starredOnly) {
      // Use starred index
      threadsQuery = ctx.db
        .query("emailThreads")
        .withIndex("by_account_starred", (q) =>
          q
            .eq("userId", args.userId)
            .eq("accountId", args.accountId)
            .eq("isStarred", true)
        );
    } else {
      // Use standard date index
      threadsQuery = ctx.db
        .query("emailThreads")
        .withIndex("by_account_date", (q) =>
          q.eq("userId", args.userId).eq("accountId", args.accountId)
        );
    }

    // Get threads with pagination
    // We fetch one extra to determine if there are more results
    let threads = await threadsQuery
      .order("desc")
      .filter((q) => {
        // Apply cursor filter if provided
        if (args.cursor) {
          return q.lt(q.field("lastMessageAt"), args.cursor);
        }
        return true;
      })
      .take(limit + 1);

    // Apply label filter in memory (since Convex doesn't support array contains in index)
    if (args.labelId) {
      threads = threads.filter((t) => t.labels.includes(args.labelId!));
    }

    // Apply search filter in memory
    if (args.query) {
      const searchLower = args.query.toLowerCase();
      threads = threads.filter(
        (t) =>
          t.subject.toLowerCase().includes(searchLower) ||
          t.snippet.toLowerCase().includes(searchLower) ||
          t.participants.some(
            (p) =>
              p.email.toLowerCase().includes(searchLower) ||
              p.name?.toLowerCase().includes(searchLower)
          )
      );
    }

    // Determine pagination
    const hasMore = threads.length > limit;
    const items = hasMore ? threads.slice(0, limit) : threads;
    const nextCursor = hasMore && items.length > 0
      ? items[items.length - 1].lastMessageAt
      : null;

    return {
      items,
      nextCursor,
      hasMore,
    };
  },
});

/**
 * Get a single thread with all its messages
 */
export const getThread = query({
  args: {
    userId: v.string(),
    accountId: v.id("emailAccounts"),
    threadId: v.string(),
  },
  handler: async (ctx, args) => {
    // Get the thread
    const thread = await ctx.db
      .query("emailThreads")
      .withIndex("by_account_threadId", (q) =>
        q
          .eq("userId", args.userId)
          .eq("accountId", args.accountId)
          .eq("threadId", args.threadId)
      )
      .unique();

    if (!thread) {
      return null;
    }

    // Get all messages in the thread, sorted by date ascending
    const messages = await ctx.db
      .query("emailMessages")
      .withIndex("by_thread", (q) =>
        q
          .eq("userId", args.userId)
          .eq("accountId", args.accountId)
          .eq("threadId", args.threadId)
      )
      .order("asc")
      .collect();

    return {
      thread,
      messages,
    };
  },
});

/**
 * Get thread by Convex ID (internal use)
 */
export const getThreadById = query({
  args: {
    userId: v.string(),
    threadId: v.id("emailThreads"),
  },
  handler: async (ctx, args) => {
    const thread = await ctx.db.get(args.threadId);

    // Verify ownership
    if (!thread || thread.userId !== args.userId) {
      return null;
    }

    return thread;
  },
});

// ============================================================================
// Message Queries
// ============================================================================

/**
 * Get a single message by provider message ID
 */
export const getMessage = query({
  args: {
    userId: v.string(),
    accountId: v.id("emailAccounts"),
    messageId: v.string(),
  },
  handler: async (ctx, args) => {
    const message = await ctx.db
      .query("emailMessages")
      .withIndex("by_account_messageId", (q) =>
        q
          .eq("userId", args.userId)
          .eq("accountId", args.accountId)
          .eq("messageId", args.messageId)
      )
      .unique();

    return message;
  },
});

/**
 * Get messages by Convex IDs (batch)
 */
export const getMessages = query({
  args: {
    userId: v.string(),
    messageIds: v.array(v.id("emailMessages")),
  },
  handler: async (ctx, args) => {
    const messages: (Doc<"emailMessages"> | null)[] = [];

    for (const messageId of args.messageIds) {
      const message = await ctx.db.get(messageId);
      // Verify ownership
      if (message && message.userId === args.userId) {
        messages.push(message);
      } else {
        messages.push(null);
      }
    }

    return messages;
  },
});

// ============================================================================
// Label Queries
// ============================================================================

/**
 * Get all labels for an account
 */
export const getLabels = query({
  args: {
    userId: v.string(),
    accountId: v.id("emailAccounts"),
  },
  handler: async (ctx, args) => {
    const labels = await ctx.db
      .query("emailLabels")
      .withIndex("by_account", (q) =>
        q.eq("userId", args.userId).eq("accountId", args.accountId)
      )
      .collect();

    return { labels };
  },
});

/**
 * Get a specific label by provider label ID
 */
export const getLabel = query({
  args: {
    userId: v.string(),
    accountId: v.id("emailAccounts"),
    labelId: v.string(),
  },
  handler: async (ctx, args) => {
    const label = await ctx.db
      .query("emailLabels")
      .withIndex("by_account_labelId", (q) =>
        q
          .eq("userId", args.userId)
          .eq("accountId", args.accountId)
          .eq("labelId", args.labelId)
      )
      .unique();

    return label;
  },
});

// ============================================================================
// Sync State Queries
// ============================================================================

/**
 * Get current sync state for an account
 */
export const getSyncState = query({
  args: {
    userId: v.string(),
    accountId: v.id("emailAccounts"),
  },
  handler: async (ctx, args) => {
    const syncState = await ctx.db
      .query("emailSyncState")
      .withIndex("by_account", (q) =>
        q.eq("userId", args.userId).eq("accountId", args.accountId)
      )
      .unique();

    return syncState;
  },
});

// ============================================================================
// Draft Queries
// ============================================================================

/**
 * Get all drafts for an account
 */
export const getDrafts = query({
  args: {
    userId: v.string(),
    accountId: v.id("emailAccounts"),
    cursor: v.optional(v.number()),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const limit = Math.min(args.limit ?? DEFAULT_PAGE_SIZE, MAX_PAGE_SIZE);

    let draftsQuery = ctx.db
      .query("emailDrafts")
      .withIndex("by_account", (q) =>
        q.eq("userId", args.userId).eq("accountId", args.accountId)
      )
      .order("desc");

    // Apply cursor filter
    if (args.cursor) {
      draftsQuery = draftsQuery.filter((q) =>
        q.lt(q.field("updatedAt"), args.cursor!)
      );
    }

    const drafts = await draftsQuery.take(limit + 1);

    const hasMore = drafts.length > limit;
    const items = hasMore ? drafts.slice(0, limit) : drafts;
    const nextCursor = hasMore && items.length > 0
      ? items[items.length - 1].updatedAt
      : null;

    return {
      items,
      nextCursor,
      hasMore,
    };
  },
});

/**
 * Get a specific draft by ID
 */
export const getDraft = query({
  args: {
    userId: v.string(),
    draftId: v.id("emailDrafts"),
  },
  handler: async (ctx, args) => {
    const draft = await ctx.db.get(args.draftId);

    // Verify ownership
    if (!draft || draft.userId !== args.userId) {
      return null;
    }

    return draft;
  },
});

/**
 * Get draft by provider draft ID
 */
export const getDraftByProviderId = query({
  args: {
    userId: v.string(),
    accountId: v.id("emailAccounts"),
    draftId: v.string(),
  },
  handler: async (ctx, args) => {
    const draft = await ctx.db
      .query("emailDrafts")
      .withIndex("by_account_draftId", (q) =>
        q
          .eq("userId", args.userId)
          .eq("accountId", args.accountId)
          .eq("draftId", args.draftId)
      )
      .unique();

    return draft;
  },
});

// ============================================================================
// Account Queries
// ============================================================================

/**
 * Get all email accounts for a user
 */
export const getAccounts = query({
  args: {
    userId: v.string(),
  },
  handler: async (ctx, args) => {
    const accounts = await ctx.db
      .query("emailAccounts")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .collect();

    // Don't return token references to client
    return accounts.map((account) => ({
      _id: account._id,
      _creationTime: account._creationTime,
      userId: account.userId,
      provider: account.provider,
      emailAddress: account.emailAddress,
      status: account.status,
      errorMessage: account.errorMessage,
      createdAt: account.createdAt,
      updatedAt: account.updatedAt,
    }));
  },
});

/**
 * Get a specific email account
 */
export const getAccount = query({
  args: {
    userId: v.string(),
    accountId: v.id("emailAccounts"),
  },
  handler: async (ctx, args) => {
    const account = await ctx.db.get(args.accountId);

    // Verify ownership
    if (!account || account.userId !== args.userId) {
      return null;
    }

    // Don't return token references to client
    return {
      _id: account._id,
      _creationTime: account._creationTime,
      userId: account.userId,
      provider: account.provider,
      emailAddress: account.emailAddress,
      status: account.status,
      errorMessage: account.errorMessage,
      createdAt: account.createdAt,
      updatedAt: account.updatedAt,
    };
  },
});

// ============================================================================
// Tombstone Queries (for sync)
// ============================================================================

/**
 * Get tombstones for incremental sync
 */
export const getTombstones = query({
  args: {
    userId: v.string(),
    entityType: v.union(
      v.literal("thread"),
      v.literal("message"),
      v.literal("label"),
      v.literal("draft"),
      v.literal("account")
    ),
    /** Only tombstones after this timestamp */
    since: v.optional(v.number()),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const limit = Math.min(args.limit ?? 100, 500);

    let query = ctx.db
      .query("emailTombstones")
      .withIndex("by_user_type", (q) =>
        q.eq("userId", args.userId).eq("entityType", args.entityType)
      )
      .order("asc");

    if (args.since) {
      query = query.filter((q) => q.gt(q.field("deletedAt"), args.since!));
    }

    const tombstones = await query.take(limit);

    return tombstones;
  },
});

// ============================================================================
// Statistics Queries
// ============================================================================

/**
 * Get email statistics for an account
 */
export const getStats = query({
  args: {
    userId: v.string(),
    accountId: v.id("emailAccounts"),
  },
  handler: async (ctx, args) => {
    // Get total thread count
    const threads = await ctx.db
      .query("emailThreads")
      .withIndex("by_account_date", (q) =>
        q.eq("userId", args.userId).eq("accountId", args.accountId)
      )
      .collect();

    const totalThreads = threads.length;
    const unreadThreads = threads.filter((t) => t.unreadCount > 0).length;
    const starredThreads = threads.filter((t) => t.isStarred).length;

    // Get draft count
    const drafts = await ctx.db
      .query("emailDrafts")
      .withIndex("by_account", (q) =>
        q.eq("userId", args.userId).eq("accountId", args.accountId)
      )
      .collect();

    return {
      totalThreads,
      unreadThreads,
      starredThreads,
      draftCount: drafts.length,
    };
  },
});
