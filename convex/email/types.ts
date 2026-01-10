/**
 * Shared TypeScript types for the Email domain
 *
 * Privacy/Consent Model:
 * - All email data is stored per-user (userId as primary partition key)
 * - Access to email data requires valid Clerk JWT with matching userId
 * - No cross-user data access is permitted
 * - Email content may be processed by the Brain for AI features only with user consent
 * - Tombstones track deletions for sync and compliance
 */

import { Id } from "../_generated/dataModel";

// ============================================================================
// Core Email Types
// ============================================================================

/**
 * Email address with optional display name
 */
export interface EmailAddress {
  email: string;
  name?: string;
}

/**
 * Email attachment metadata
 */
export interface EmailAttachment {
  id: string;
  filename: string;
  mimeType: string;
  size: number;
  /** Storage reference for attachment content */
  contentRef?: string;
  /** For inline attachments (images in HTML body) */
  contentId?: string;
  isInline: boolean;
}

/**
 * Email account connection status
 */
export type AccountStatus = "active" | "disconnected" | "error";

/**
 * Supported email providers
 */
export type EmailProvider = "gmail" | "imap" | "outlook";

/**
 * Label type - system labels are managed by provider, user labels are custom
 */
export type LabelType = "system" | "user";

/**
 * Email account representation
 */
export interface EmailAccount {
  _id: Id<"emailAccounts">;
  userId: string;
  provider: EmailProvider;
  emailAddress: string;
  /** Reference to encrypted access token in secure storage */
  accessTokenRef?: string;
  /** Reference to encrypted refresh token in secure storage */
  refreshTokenRef?: string;
  status: AccountStatus;
  createdAt: number;
  updatedAt: number;
}

/**
 * Email thread (conversation)
 */
export interface EmailThread {
  _id: Id<"emailThreads">;
  userId: string;
  accountId: Id<"emailAccounts">;
  /** Provider-specific thread ID (e.g., Gmail thread ID) */
  threadId: string;
  /** Short preview of the latest message */
  snippet: string;
  /** Subject line of the thread */
  subject: string;
  /** Timestamp of the most recent message */
  lastMessageAt: number;
  /** Number of unread messages in thread */
  unreadCount: number;
  /** Labels applied to this thread */
  labels: string[];
  /** Email addresses of all participants */
  participants: EmailAddress[];
  /** Whether any message has attachments */
  hasAttachments: boolean;
  /** Whether thread is starred */
  isStarred: boolean;
  /** Last update timestamp */
  updatedAt: number;
}

/**
 * Individual email message
 */
export interface EmailMessage {
  _id: Id<"emailMessages">;
  userId: string;
  accountId: Id<"emailAccounts">;
  /** Provider-specific message ID */
  messageId: string;
  /** Thread this message belongs to */
  threadId: string;
  /** Sender */
  from: EmailAddress;
  /** Recipients */
  to: EmailAddress[];
  /** CC recipients */
  cc: EmailAddress[];
  /** BCC recipients (only for sent messages) */
  bcc: EmailAddress[];
  /** Subject line */
  subject: string;
  /** Short preview text */
  snippet: string;
  /** Storage reference for plain text body */
  bodyRef?: string;
  /** Storage reference for HTML body */
  htmlBodyRef?: string;
  /** Provider's internal date (for sorting) */
  internalDate: number;
  /** Attachments metadata */
  attachments: EmailAttachment[];
  /** Provider label IDs */
  labelIds: string[];
  /** Email headers (selected important ones) */
  headers: Record<string, string>;
  /** Read status */
  isRead: boolean;
  /** Starred status */
  isStarred: boolean;
}

/**
 * Email label (folder/tag)
 */
export interface EmailLabel {
  _id: Id<"emailLabels">;
  userId: string;
  accountId: Id<"emailAccounts">;
  /** Provider-specific label ID */
  labelId: string;
  /** Display name */
  name: string;
  /** System or user-created */
  type: LabelType;
  /** Optional color for UI */
  color?: string;
  /** Total messages with this label */
  messageCount: number;
  /** Unread messages with this label */
  unreadCount: number;
}

/**
 * Sync state for incremental sync
 */
export interface EmailSyncState {
  _id: Id<"emailSyncState">;
  userId: string;
  accountId: Id<"emailAccounts">;
  /** Gmail historyId or IMAP UIDVALIDITY+UID cursor */
  historyId?: string;
  /** Generic cursor for pagination during full sync */
  cursor?: string;
  /** Last successful sync timestamp */
  lastSyncAt: number;
  /** Current sync status */
  syncStatus: "idle" | "syncing" | "error";
  /** Error message if status is error */
  errorMessage?: string;
}

/**
 * Email draft
 */
export interface EmailDraft {
  _id: Id<"emailDrafts">;
  userId: string;
  accountId: Id<"emailAccounts">;
  /** Provider draft ID if synced */
  draftId?: string;
  /** Recipients */
  to: EmailAddress[];
  /** CC recipients */
  cc: EmailAddress[];
  /** BCC recipients */
  bcc: EmailAddress[];
  /** Subject */
  subject: string;
  /** Draft body (plain text) */
  body: string;
  /** HTML body if composed with rich text */
  htmlBody?: string;
  /** Attachments to send */
  attachments: EmailAttachment[];
  /** Reply to message ID */
  replyToMessageId?: string;
  /** Forward from message ID */
  forwardFromMessageId?: string;
  createdAt: number;
  updatedAt: number;
}

/**
 * Tombstone for tracking deletions
 */
export interface EmailTombstone {
  _id: Id<"emailTombstones">;
  userId: string;
  entityType: "thread" | "message" | "label" | "draft" | "account";
  /** Original entity ID */
  entityId: string;
  /** When the deletion occurred */
  deletedAt: number;
}

// ============================================================================
// Action Types
// ============================================================================

/**
 * Actions that can be applied to email threads/messages
 */
export type EmailActionType =
  | "archive"
  | "unarchive"
  | "trash"
  | "untrash"
  | "delete"
  | "star"
  | "unstar"
  | "markRead"
  | "markUnread"
  | "addLabel"
  | "removeLabel"
  | "spam"
  | "notSpam"
  | "moveToInbox";

/**
 * Action request for applying to threads
 */
export interface EmailActionRequest {
  /** Thread IDs to apply action to */
  threadIds: string[];
  /** Action to apply */
  action: EmailActionType;
  /** Label ID for addLabel/removeLabel actions */
  labelId?: string;
  /** Idempotency key for deduplication */
  idempotencyKey?: string;
}

// ============================================================================
// Request/Response DTOs
// ============================================================================

/**
 * Pagination cursor (opaque to client)
 */
export interface PaginationCursor {
  /** Encoded cursor string */
  cursor: string | null;
  /** Whether more results exist */
  hasMore: boolean;
}

/**
 * Paginated response wrapper
 */
export interface PaginatedResponse<T> {
  items: T[];
  nextCursor: string | null;
  hasMore: boolean;
}

/**
 * List threads request
 */
export interface ListThreadsRequest {
  accountId: string;
  /** Filter by label ID */
  labelId?: string;
  /** Basic search query */
  query?: string;
  /** Pagination cursor */
  cursor?: string;
  /** Page size (default 50, max 100) */
  limit?: number;
}

/**
 * List threads response
 */
export interface ListThreadsResponse extends PaginatedResponse<EmailThread> {}

/**
 * Get thread request
 */
export interface GetThreadRequest {
  accountId: string;
  threadId: string;
}

/**
 * Get thread response
 */
export interface GetThreadResponse {
  thread: EmailThread;
  messages: EmailMessage[];
}

/**
 * Apply action request
 */
export interface ApplyActionRequest {
  accountId: string;
  actions: EmailActionRequest[];
}

/**
 * Apply action response
 */
export interface ApplyActionResponse {
  success: boolean;
  /** Number of threads affected */
  affectedCount: number;
  /** Any errors that occurred */
  errors?: Array<{
    threadId: string;
    error: string;
  }>;
}

/**
 * Create draft request
 */
export interface CreateDraftRequest {
  accountId: string;
  to: EmailAddress[];
  cc?: EmailAddress[];
  bcc?: EmailAddress[];
  subject: string;
  body: string;
  htmlBody?: string;
  replyToMessageId?: string;
  forwardFromMessageId?: string;
}

/**
 * Update draft request
 */
export interface UpdateDraftRequest {
  accountId: string;
  draftId: string;
  to?: EmailAddress[];
  cc?: EmailAddress[];
  bcc?: EmailAddress[];
  subject?: string;
  body?: string;
  htmlBody?: string;
}

/**
 * Send draft request
 */
export interface SendDraftRequest {
  accountId: string;
  draftId: string;
}

/**
 * Get labels response
 */
export interface GetLabelsResponse {
  labels: EmailLabel[];
}

/**
 * Create label request
 */
export interface CreateLabelRequest {
  accountId: string;
  name: string;
  color?: string;
}

/**
 * Batch insert messages request (for connector use)
 */
export interface BatchInsertMessagesRequest {
  accountId: string;
  messages: Array<{
    messageId: string;
    threadId: string;
    from: EmailAddress;
    to: EmailAddress[];
    cc?: EmailAddress[];
    bcc?: EmailAddress[];
    subject: string;
    snippet: string;
    body?: string;
    htmlBody?: string;
    internalDate: number;
    attachments?: EmailAttachment[];
    labelIds: string[];
    headers?: Record<string, string>;
    isRead: boolean;
    isStarred: boolean;
  }>;
  /** Update sync state after insert */
  syncState?: {
    historyId?: string;
    cursor?: string;
  };
}

/**
 * API Error response
 */
export interface ApiErrorResponse {
  error: string;
  code: string;
  details?: Record<string, unknown>;
}

// ============================================================================
// Event Types (for Brain processing)
// ============================================================================

/**
 * Brain processing status for events
 */
export type BrainStatus = "pending" | "processing" | "processed" | "failed" | "skipped";

/**
 * Email event types for the append-only event store
 */
export type EmailEventType =
  | "email.message.received"
  | "email.message.sent"
  | "email.thread.updated"
  | "email.action.applied"
  | "email.draft.created"
  | "email.draft.updated"
  | "email.draft.deleted"
  | "email.label.created"
  | "email.label.deleted"
  | "email.account.connected"
  | "email.account.disconnected"
  | "email.sync.completed";

/**
 * Base event structure
 */
export interface EmailEvent {
  _id: Id<"events">;
  userId: string;
  type: EmailEventType;
  /** Event payload (type-specific) */
  payload: Record<string, unknown>;
  /** When the event occurred */
  timestamp: number;
  /** Status for Brain AI processing */
  brainStatus: BrainStatus;
  /** Idempotency key for deduplication */
  idempotencyKey?: string;
}

// ============================================================================
// Utility Types
// ============================================================================

/**
 * Result type for operations that can fail
 */
export type Result<T, E = string> =
  | { success: true; data: T }
  | { success: false; error: E };

/**
 * Verification result from Clerk JWT
 */
export interface ClerkVerificationResult {
  userId: string;
  sessionId: string;
  /** Token expiration timestamp */
  exp: number;
}
