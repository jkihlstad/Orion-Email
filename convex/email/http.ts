/**
 * HTTP Actions (REST Endpoints) for Email API
 *
 * These endpoints provide a REST interface for the iOS app.
 * All endpoints:
 * - Verify Clerk JWT via Authorization header
 * - Return proper HTTP status codes
 * - Handle errors gracefully
 *
 * Privacy/Consent Model:
 * - All endpoints require authentication
 * - User can only access their own data
 * - No cross-user data access is permitted
 */

import { httpRouter } from "convex/server";
import { httpAction } from "../_generated/server";
import { api, internal } from "../_generated/api";
import { verifyClerkJwt, AuthenticationError } from "../auth/verifyClerk";
import { Id } from "../_generated/dataModel";

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Create a JSON response with proper headers
 */
function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
    },
  });
}

/**
 * Create an error response
 */
function errorResponse(
  message: string,
  code: string,
  status: number,
  details?: Record<string, unknown>
): Response {
  return jsonResponse({ error: message, code, details }, status);
}

/**
 * Handle CORS preflight requests
 */
function corsResponse(): Response {
  return new Response(null, {
    status: 204,
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Access-Control-Max-Age": "86400",
    },
  });
}

/**
 * Parse JSON body safely
 */
async function parseBody<T>(request: Request): Promise<T | null> {
  try {
    const text = await request.text();
    if (!text) return null;
    return JSON.parse(text) as T;
  } catch {
    return null;
  }
}

// ============================================================================
// HTTP Router
// ============================================================================

const http = httpRouter();

// ============================================================================
// Sync Endpoints
// ============================================================================

/**
 * POST /email/sync/listThreads
 * List email threads with pagination, label filter, and search
 */
http.route({
  path: "/email/sync/listThreads",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    // Handle CORS preflight
    if (request.method === "OPTIONS") {
      return corsResponse();
    }

    try {
      // Verify authentication
      const auth = await verifyClerkJwt(ctx, request.headers.get("Authorization"));

      // Parse request body
      const body = await parseBody<{
        accountId: string;
        labelId?: string;
        query?: string;
        cursor?: string;
        limit?: number;
        starredOnly?: boolean;
      }>(request);

      if (!body?.accountId) {
        return errorResponse("accountId is required", "INVALID_REQUEST", 400);
      }

      // Call the query
      const result = await ctx.runQuery(api.email.queries.listThreads, {
        userId: auth.userId,
        accountId: body.accountId as Id<"emailAccounts">,
        labelId: body.labelId,
        query: body.query,
        cursor: body.cursor ? parseFloat(body.cursor) : undefined,
        limit: body.limit,
        starredOnly: body.starredOnly,
      });

      return jsonResponse({
        items: result.items,
        nextCursor: result.nextCursor?.toString() ?? null,
        hasMore: result.hasMore,
      });
    } catch (error) {
      if (error instanceof AuthenticationError) {
        return errorResponse(error.message, error.code, 401);
      }
      console.error("listThreads error:", error);
      return errorResponse("Internal server error", "INTERNAL_ERROR", 500);
    }
  }),
});

/**
 * POST /email/sync/getThread
 * Get a single thread with all its messages
 */
http.route({
  path: "/email/sync/getThread",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    if (request.method === "OPTIONS") {
      return corsResponse();
    }

    try {
      const auth = await verifyClerkJwt(ctx, request.headers.get("Authorization"));

      const body = await parseBody<{
        accountId: string;
        threadId: string;
      }>(request);

      if (!body?.accountId || !body?.threadId) {
        return errorResponse(
          "accountId and threadId are required",
          "INVALID_REQUEST",
          400
        );
      }

      const result = await ctx.runQuery(api.email.queries.getThread, {
        userId: auth.userId,
        accountId: body.accountId as Id<"emailAccounts">,
        threadId: body.threadId,
      });

      if (!result) {
        return errorResponse("Thread not found", "NOT_FOUND", 404);
      }

      return jsonResponse(result);
    } catch (error) {
      if (error instanceof AuthenticationError) {
        return errorResponse(error.message, error.code, 401);
      }
      console.error("getThread error:", error);
      return errorResponse("Internal server error", "INTERNAL_ERROR", 500);
    }
  }),
});

// ============================================================================
// Action Endpoints
// ============================================================================

/**
 * POST /email/actions/apply
 * Apply actions to threads (archive, trash, star, read, label, etc.)
 */
http.route({
  path: "/email/actions/apply",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    if (request.method === "OPTIONS") {
      return corsResponse();
    }

    try {
      const auth = await verifyClerkJwt(ctx, request.headers.get("Authorization"));

      const body = await parseBody<{
        accountId: string;
        actions: Array<{
          threadIds: string[];
          action: string;
          labelId?: string;
          idempotencyKey?: string;
        }>;
      }>(request);

      if (!body?.accountId || !body?.actions || body.actions.length === 0) {
        return errorResponse(
          "accountId and actions are required",
          "INVALID_REQUEST",
          400
        );
      }

      const results = [];
      for (const action of body.actions) {
        const result = await ctx.runMutation(api.email.mutations.applyAction, {
          userId: auth.userId,
          accountId: body.accountId as Id<"emailAccounts">,
          threadIds: action.threadIds,
          action: action.action as any,
          labelId: action.labelId,
          idempotencyKey: action.idempotencyKey,
        });
        results.push(result);
      }

      // Aggregate results
      const totalAffected = results.reduce((sum, r) => sum + r.affectedCount, 0);
      const allErrors = results.flatMap((r) => r.errors ?? []);

      return jsonResponse({
        success: allErrors.length === 0,
        affectedCount: totalAffected,
        errors: allErrors.length > 0 ? allErrors : undefined,
      });
    } catch (error) {
      if (error instanceof AuthenticationError) {
        return errorResponse(error.message, error.code, 401);
      }
      console.error("applyAction error:", error);
      return errorResponse("Internal server error", "INTERNAL_ERROR", 500);
    }
  }),
});

// ============================================================================
// Send/Draft Endpoints
// ============================================================================

/**
 * POST /email/send/createDraft
 * Create a new email draft
 */
http.route({
  path: "/email/send/createDraft",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    if (request.method === "OPTIONS") {
      return corsResponse();
    }

    try {
      const auth = await verifyClerkJwt(ctx, request.headers.get("Authorization"));

      const body = await parseBody<{
        accountId: string;
        to: Array<{ email: string; name?: string }>;
        cc?: Array<{ email: string; name?: string }>;
        bcc?: Array<{ email: string; name?: string }>;
        subject: string;
        body: string;
        htmlBody?: string;
        replyToMessageId?: string;
        forwardFromMessageId?: string;
        idempotencyKey?: string;
      }>(request);

      if (!body?.accountId || !body?.to || !body?.subject) {
        return errorResponse(
          "accountId, to, and subject are required",
          "INVALID_REQUEST",
          400
        );
      }

      const result = await ctx.runMutation(api.email.mutations.createDraft, {
        userId: auth.userId,
        accountId: body.accountId as Id<"emailAccounts">,
        to: body.to,
        cc: body.cc,
        bcc: body.bcc,
        subject: body.subject,
        body: body.body ?? "",
        htmlBody: body.htmlBody,
        replyToMessageId: body.replyToMessageId,
        forwardFromMessageId: body.forwardFromMessageId,
        idempotencyKey: body.idempotencyKey,
      });

      return jsonResponse(result, 201);
    } catch (error) {
      if (error instanceof AuthenticationError) {
        return errorResponse(error.message, error.code, 401);
      }
      console.error("createDraft error:", error);
      return errorResponse("Internal server error", "INTERNAL_ERROR", 500);
    }
  }),
});

/**
 * POST /email/send/updateDraft
 * Update an existing draft
 */
http.route({
  path: "/email/send/updateDraft",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    if (request.method === "OPTIONS") {
      return corsResponse();
    }

    try {
      const auth = await verifyClerkJwt(ctx, request.headers.get("Authorization"));

      const body = await parseBody<{
        draftId: string;
        to?: Array<{ email: string; name?: string }>;
        cc?: Array<{ email: string; name?: string }>;
        bcc?: Array<{ email: string; name?: string }>;
        subject?: string;
        body?: string;
        htmlBody?: string;
      }>(request);

      if (!body?.draftId) {
        return errorResponse("draftId is required", "INVALID_REQUEST", 400);
      }

      const result = await ctx.runMutation(api.email.mutations.updateDraft, {
        userId: auth.userId,
        draftId: body.draftId as Id<"emailDrafts">,
        to: body.to,
        cc: body.cc,
        bcc: body.bcc,
        subject: body.subject,
        body: body.body,
        htmlBody: body.htmlBody,
      });

      return jsonResponse(result);
    } catch (error) {
      if (error instanceof AuthenticationError) {
        return errorResponse(error.message, error.code, 401);
      }
      if (error instanceof Error && error.message.includes("not found")) {
        return errorResponse("Draft not found", "NOT_FOUND", 404);
      }
      console.error("updateDraft error:", error);
      return errorResponse("Internal server error", "INTERNAL_ERROR", 500);
    }
  }),
});

/**
 * POST /email/send/sendDraft
 * Send a draft email (queues for connector)
 */
http.route({
  path: "/email/send/sendDraft",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    if (request.method === "OPTIONS") {
      return corsResponse();
    }

    try {
      const auth = await verifyClerkJwt(ctx, request.headers.get("Authorization"));

      const body = await parseBody<{
        draftId: string;
        idempotencyKey?: string;
      }>(request);

      if (!body?.draftId) {
        return errorResponse("draftId is required", "INVALID_REQUEST", 400);
      }

      const result = await ctx.runMutation(api.email.mutations.sendDraft, {
        userId: auth.userId,
        draftId: body.draftId as Id<"emailDrafts">,
        idempotencyKey: body.idempotencyKey,
      });

      return jsonResponse(result);
    } catch (error) {
      if (error instanceof AuthenticationError) {
        return errorResponse(error.message, error.code, 401);
      }
      if (error instanceof Error && error.message.includes("not found")) {
        return errorResponse("Draft not found", "NOT_FOUND", 404);
      }
      console.error("sendDraft error:", error);
      return errorResponse("Internal server error", "INTERNAL_ERROR", 500);
    }
  }),
});

/**
 * DELETE /email/send/deleteDraft
 * Delete a draft
 */
http.route({
  path: "/email/send/deleteDraft",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    if (request.method === "OPTIONS") {
      return corsResponse();
    }

    try {
      const auth = await verifyClerkJwt(ctx, request.headers.get("Authorization"));

      const body = await parseBody<{
        draftId: string;
      }>(request);

      if (!body?.draftId) {
        return errorResponse("draftId is required", "INVALID_REQUEST", 400);
      }

      const result = await ctx.runMutation(api.email.mutations.deleteDraft, {
        userId: auth.userId,
        draftId: body.draftId as Id<"emailDrafts">,
      });

      return jsonResponse(result);
    } catch (error) {
      if (error instanceof AuthenticationError) {
        return errorResponse(error.message, error.code, 401);
      }
      if (error instanceof Error && error.message.includes("not found")) {
        return errorResponse("Draft not found", "NOT_FOUND", 404);
      }
      console.error("deleteDraft error:", error);
      return errorResponse("Internal server error", "INTERNAL_ERROR", 500);
    }
  }),
});

// ============================================================================
// Ingest Endpoints (for Connector use)
// ============================================================================

/**
 * POST /email/ingest/insertBatch
 * Batch insert messages from sync (for connector use)
 */
http.route({
  path: "/email/ingest/insertBatch",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    if (request.method === "OPTIONS") {
      return corsResponse();
    }

    try {
      const auth = await verifyClerkJwt(ctx, request.headers.get("Authorization"));

      const body = await parseBody<{
        accountId: string;
        messages: Array<{
          messageId: string;
          threadId: string;
          from: { email: string; name?: string };
          to: Array<{ email: string; name?: string }>;
          cc?: Array<{ email: string; name?: string }>;
          bcc?: Array<{ email: string; name?: string }>;
          subject: string;
          snippet: string;
          bodyRef?: string;
          htmlBodyRef?: string;
          internalDate: number;
          attachments?: Array<{
            id: string;
            filename: string;
            mimeType: string;
            size: number;
            contentRef?: string;
            contentId?: string;
            isInline: boolean;
          }>;
          labelIds: string[];
          headers?: Record<string, string>;
          isRead: boolean;
          isStarred: boolean;
        }>;
        syncState?: {
          historyId?: string;
          cursor?: string;
        };
      }>(request);

      if (!body?.accountId || !body?.messages) {
        return errorResponse(
          "accountId and messages are required",
          "INVALID_REQUEST",
          400
        );
      }

      const result = await ctx.runMutation(api.email.mutations.batchInsertMessages, {
        userId: auth.userId,
        accountId: body.accountId as Id<"emailAccounts">,
        messages: body.messages,
        syncState: body.syncState,
      });

      return jsonResponse(result);
    } catch (error) {
      if (error instanceof AuthenticationError) {
        return errorResponse(error.message, error.code, 401);
      }
      console.error("insertBatch error:", error);
      return errorResponse("Internal server error", "INTERNAL_ERROR", 500);
    }
  }),
});

// ============================================================================
// Label Endpoints
// ============================================================================

/**
 * GET /email/labels
 * Get all labels for an account
 */
http.route({
  path: "/email/labels",
  method: "GET",
  handler: httpAction(async (ctx, request) => {
    if (request.method === "OPTIONS") {
      return corsResponse();
    }

    try {
      const auth = await verifyClerkJwt(ctx, request.headers.get("Authorization"));

      // Get accountId from query params
      const url = new URL(request.url);
      const accountId = url.searchParams.get("accountId");

      if (!accountId) {
        return errorResponse("accountId query param is required", "INVALID_REQUEST", 400);
      }

      const result = await ctx.runQuery(api.email.queries.getLabels, {
        userId: auth.userId,
        accountId: accountId as Id<"emailAccounts">,
      });

      return jsonResponse(result);
    } catch (error) {
      if (error instanceof AuthenticationError) {
        return errorResponse(error.message, error.code, 401);
      }
      console.error("getLabels error:", error);
      return errorResponse("Internal server error", "INTERNAL_ERROR", 500);
    }
  }),
});

/**
 * POST /email/labels/create
 * Create a new user label
 */
http.route({
  path: "/email/labels/create",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    if (request.method === "OPTIONS") {
      return corsResponse();
    }

    try {
      const auth = await verifyClerkJwt(ctx, request.headers.get("Authorization"));

      const body = await parseBody<{
        accountId: string;
        name: string;
        color?: string;
        idempotencyKey?: string;
      }>(request);

      if (!body?.accountId || !body?.name) {
        return errorResponse(
          "accountId and name are required",
          "INVALID_REQUEST",
          400
        );
      }

      const result = await ctx.runMutation(api.email.mutations.addLabel, {
        userId: auth.userId,
        accountId: body.accountId as Id<"emailAccounts">,
        name: body.name,
        color: body.color,
        idempotencyKey: body.idempotencyKey,
      });

      return jsonResponse(result, 201);
    } catch (error) {
      if (error instanceof AuthenticationError) {
        return errorResponse(error.message, error.code, 401);
      }
      console.error("createLabel error:", error);
      return errorResponse("Internal server error", "INTERNAL_ERROR", 500);
    }
  }),
});

/**
 * DELETE /email/labels/:id
 * Delete a user label
 */
http.route({
  path: "/email/labels/delete",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    if (request.method === "OPTIONS") {
      return corsResponse();
    }

    try {
      const auth = await verifyClerkJwt(ctx, request.headers.get("Authorization"));

      const body = await parseBody<{
        labelId: string;
      }>(request);

      if (!body?.labelId) {
        return errorResponse("labelId is required", "INVALID_REQUEST", 400);
      }

      const result = await ctx.runMutation(api.email.mutations.deleteLabel, {
        userId: auth.userId,
        labelId: body.labelId as Id<"emailLabels">,
      });

      return jsonResponse(result);
    } catch (error) {
      if (error instanceof AuthenticationError) {
        return errorResponse(error.message, error.code, 401);
      }
      if (error instanceof Error && error.message.includes("not found")) {
        return errorResponse("Label not found", "NOT_FOUND", 404);
      }
      if (error instanceof Error && error.message.includes("system labels")) {
        return errorResponse("Cannot delete system labels", "FORBIDDEN", 403);
      }
      console.error("deleteLabel error:", error);
      return errorResponse("Internal server error", "INTERNAL_ERROR", 500);
    }
  }),
});

// ============================================================================
// Account Endpoints
// ============================================================================

/**
 * GET /email/accounts
 * Get all email accounts for the user
 */
http.route({
  path: "/email/accounts",
  method: "GET",
  handler: httpAction(async (ctx, request) => {
    if (request.method === "OPTIONS") {
      return corsResponse();
    }

    try {
      const auth = await verifyClerkJwt(ctx, request.headers.get("Authorization"));

      const result = await ctx.runQuery(api.email.queries.getAccounts, {
        userId: auth.userId,
      });

      return jsonResponse({ accounts: result });
    } catch (error) {
      if (error instanceof AuthenticationError) {
        return errorResponse(error.message, error.code, 401);
      }
      console.error("getAccounts error:", error);
      return errorResponse("Internal server error", "INTERNAL_ERROR", 500);
    }
  }),
});

/**
 * POST /email/accounts/connect
 * Connect a new email account
 */
http.route({
  path: "/email/accounts/connect",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    if (request.method === "OPTIONS") {
      return corsResponse();
    }

    try {
      const auth = await verifyClerkJwt(ctx, request.headers.get("Authorization"));

      const body = await parseBody<{
        provider: "gmail" | "imap" | "outlook";
        emailAddress: string;
        accessTokenRef?: string;
        refreshTokenRef?: string;
      }>(request);

      if (!body?.provider || !body?.emailAddress) {
        return errorResponse(
          "provider and emailAddress are required",
          "INVALID_REQUEST",
          400
        );
      }

      const result = await ctx.runMutation(api.email.mutations.upsertAccount, {
        userId: auth.userId,
        provider: body.provider,
        emailAddress: body.emailAddress,
        accessTokenRef: body.accessTokenRef,
        refreshTokenRef: body.refreshTokenRef,
        status: "active",
      });

      return jsonResponse(result, result.isNew ? 201 : 200);
    } catch (error) {
      if (error instanceof AuthenticationError) {
        return errorResponse(error.message, error.code, 401);
      }
      console.error("connectAccount error:", error);
      return errorResponse("Internal server error", "INTERNAL_ERROR", 500);
    }
  }),
});

/**
 * POST /email/accounts/disconnect
 * Disconnect an email account
 */
http.route({
  path: "/email/accounts/disconnect",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    if (request.method === "OPTIONS") {
      return corsResponse();
    }

    try {
      const auth = await verifyClerkJwt(ctx, request.headers.get("Authorization"));

      const body = await parseBody<{
        accountId: string;
      }>(request);

      if (!body?.accountId) {
        return errorResponse("accountId is required", "INVALID_REQUEST", 400);
      }

      const result = await ctx.runMutation(api.email.mutations.disconnectAccount, {
        userId: auth.userId,
        accountId: body.accountId as Id<"emailAccounts">,
      });

      return jsonResponse(result);
    } catch (error) {
      if (error instanceof AuthenticationError) {
        return errorResponse(error.message, error.code, 401);
      }
      if (error instanceof Error && error.message.includes("not found")) {
        return errorResponse("Account not found", "NOT_FOUND", 404);
      }
      console.error("disconnectAccount error:", error);
      return errorResponse("Internal server error", "INTERNAL_ERROR", 500);
    }
  }),
});

// ============================================================================
// Sync State Endpoint
// ============================================================================

/**
 * GET /email/sync/state
 * Get current sync state for an account
 */
http.route({
  path: "/email/sync/state",
  method: "GET",
  handler: httpAction(async (ctx, request) => {
    if (request.method === "OPTIONS") {
      return corsResponse();
    }

    try {
      const auth = await verifyClerkJwt(ctx, request.headers.get("Authorization"));

      const url = new URL(request.url);
      const accountId = url.searchParams.get("accountId");

      if (!accountId) {
        return errorResponse("accountId query param is required", "INVALID_REQUEST", 400);
      }

      const result = await ctx.runQuery(api.email.queries.getSyncState, {
        userId: auth.userId,
        accountId: accountId as Id<"emailAccounts">,
      });

      return jsonResponse(result ?? { syncStatus: "idle", lastSyncAt: 0 });
    } catch (error) {
      if (error instanceof AuthenticationError) {
        return errorResponse(error.message, error.code, 401);
      }
      console.error("getSyncState error:", error);
      return errorResponse("Internal server error", "INTERNAL_ERROR", 500);
    }
  }),
});

/**
 * POST /email/sync/updateState
 * Update sync state (for connector use)
 */
http.route({
  path: "/email/sync/updateState",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    if (request.method === "OPTIONS") {
      return corsResponse();
    }

    try {
      const auth = await verifyClerkJwt(ctx, request.headers.get("Authorization"));

      const body = await parseBody<{
        accountId: string;
        historyId?: string;
        cursor?: string;
        syncStatus: "idle" | "syncing" | "error";
        errorMessage?: string;
      }>(request);

      if (!body?.accountId || !body?.syncStatus) {
        return errorResponse(
          "accountId and syncStatus are required",
          "INVALID_REQUEST",
          400
        );
      }

      const result = await ctx.runMutation(api.email.mutations.updateSyncState, {
        userId: auth.userId,
        accountId: body.accountId as Id<"emailAccounts">,
        historyId: body.historyId,
        cursor: body.cursor,
        syncStatus: body.syncStatus,
        errorMessage: body.errorMessage,
      });

      return jsonResponse(result);
    } catch (error) {
      if (error instanceof AuthenticationError) {
        return errorResponse(error.message, error.code, 401);
      }
      console.error("updateSyncState error:", error);
      return errorResponse("Internal server error", "INTERNAL_ERROR", 500);
    }
  }),
});

// ============================================================================
// Drafts Endpoint
// ============================================================================

/**
 * GET /email/drafts
 * Get all drafts for an account
 */
http.route({
  path: "/email/drafts",
  method: "GET",
  handler: httpAction(async (ctx, request) => {
    if (request.method === "OPTIONS") {
      return corsResponse();
    }

    try {
      const auth = await verifyClerkJwt(ctx, request.headers.get("Authorization"));

      const url = new URL(request.url);
      const accountId = url.searchParams.get("accountId");
      const cursor = url.searchParams.get("cursor");
      const limit = url.searchParams.get("limit");

      if (!accountId) {
        return errorResponse("accountId query param is required", "INVALID_REQUEST", 400);
      }

      const result = await ctx.runQuery(api.email.queries.getDrafts, {
        userId: auth.userId,
        accountId: accountId as Id<"emailAccounts">,
        cursor: cursor ? parseFloat(cursor) : undefined,
        limit: limit ? parseInt(limit, 10) : undefined,
      });

      return jsonResponse({
        items: result.items,
        nextCursor: result.nextCursor?.toString() ?? null,
        hasMore: result.hasMore,
      });
    } catch (error) {
      if (error instanceof AuthenticationError) {
        return errorResponse(error.message, error.code, 401);
      }
      console.error("getDrafts error:", error);
      return errorResponse("Internal server error", "INTERNAL_ERROR", 500);
    }
  }),
});

// ============================================================================
// CORS Preflight Handler (catch-all for OPTIONS)
// ============================================================================

// Handle OPTIONS for all paths
http.route({
  path: "/email/sync/listThreads",
  method: "OPTIONS",
  handler: httpAction(async () => corsResponse()),
});

http.route({
  path: "/email/sync/getThread",
  method: "OPTIONS",
  handler: httpAction(async () => corsResponse()),
});

http.route({
  path: "/email/actions/apply",
  method: "OPTIONS",
  handler: httpAction(async () => corsResponse()),
});

http.route({
  path: "/email/send/createDraft",
  method: "OPTIONS",
  handler: httpAction(async () => corsResponse()),
});

http.route({
  path: "/email/send/updateDraft",
  method: "OPTIONS",
  handler: httpAction(async () => corsResponse()),
});

http.route({
  path: "/email/send/sendDraft",
  method: "OPTIONS",
  handler: httpAction(async () => corsResponse()),
});

http.route({
  path: "/email/send/deleteDraft",
  method: "OPTIONS",
  handler: httpAction(async () => corsResponse()),
});

http.route({
  path: "/email/ingest/insertBatch",
  method: "OPTIONS",
  handler: httpAction(async () => corsResponse()),
});

http.route({
  path: "/email/labels",
  method: "OPTIONS",
  handler: httpAction(async () => corsResponse()),
});

http.route({
  path: "/email/labels/create",
  method: "OPTIONS",
  handler: httpAction(async () => corsResponse()),
});

http.route({
  path: "/email/labels/delete",
  method: "OPTIONS",
  handler: httpAction(async () => corsResponse()),
});

http.route({
  path: "/email/accounts",
  method: "OPTIONS",
  handler: httpAction(async () => corsResponse()),
});

http.route({
  path: "/email/accounts/connect",
  method: "OPTIONS",
  handler: httpAction(async () => corsResponse()),
});

http.route({
  path: "/email/accounts/disconnect",
  method: "OPTIONS",
  handler: httpAction(async () => corsResponse()),
});

http.route({
  path: "/email/sync/state",
  method: "OPTIONS",
  handler: httpAction(async () => corsResponse()),
});

http.route({
  path: "/email/sync/updateState",
  method: "OPTIONS",
  handler: httpAction(async () => corsResponse()),
});

http.route({
  path: "/email/drafts",
  method: "OPTIONS",
  handler: httpAction(async () => corsResponse()),
});

export default http;
