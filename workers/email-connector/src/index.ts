/**
 * Email Connector Worker
 * System #4 - Connector Service
 *
 * This worker fetches emails from providers (Gmail, Outlook, IMAP) and
 * ingests them into Convex via the /email/ingest/insertBatch endpoint.
 *
 * It runs as a scheduled worker or can be triggered via HTTP.
 */

import { Hono } from 'hono';
import { cors } from 'hono/cors';

// Types
interface EmailAccount {
  id: string;
  userId: string;
  provider: 'gmail' | 'outlook' | 'imap';
  emailAddress: string;
  accessToken: string;
  refreshToken: string;
  historyId?: string;
  cursor?: string;
}

interface RawEmailMessage {
  messageId: string;
  threadId: string;
  from: EmailParticipant;
  to: EmailParticipant[];
  cc: EmailParticipant[];
  bcc: EmailParticipant[];
  subject: string;
  snippet: string;
  bodyText?: string;
  bodyHtml?: string;
  internalDate: number;
  labelIds: string[];
  attachments: EmailAttachment[];
  headers: Record<string, string>;
}

interface EmailParticipant {
  name?: string;
  email: string;
}

interface EmailAttachment {
  id: string;
  filename: string;
  mimeType: string;
  size: number;
}

interface SyncResult {
  messagesIngested: number;
  threadsUpdated: number;
  newHistoryId?: string;
  errors: string[];
}

// Environment bindings
interface Env {
  CONVEX_URL: string;
  CONVEX_DEPLOY_KEY: string;
  GOOGLE_CLIENT_ID: string;
  GOOGLE_CLIENT_SECRET: string;
  OUTLOOK_CLIENT_ID: string;
  OUTLOOK_CLIENT_SECRET: string;
}

const app = new Hono<{ Bindings: Env }>();

app.use('/*', cors());

/**
 * Health check endpoint
 */
app.get('/health', (c) => {
  return c.json({ status: 'ok', service: 'email-connector' });
});

/**
 * Trigger sync for a specific account
 * Called by scheduled job or manual trigger
 */
app.post('/sync/:accountId', async (c) => {
  const accountId = c.req.param('accountId');
  const env = c.env;

  try {
    // 1. Fetch account details from Convex
    const account = await fetchAccount(env, accountId);
    if (!account) {
      return c.json({ error: 'Account not found' }, 404);
    }

    // 2. Sync based on provider
    let result: SyncResult;
    switch (account.provider) {
      case 'gmail':
        result = await syncGmailAccount(env, account);
        break;
      case 'outlook':
        result = await syncOutlookAccount(env, account);
        break;
      case 'imap':
        result = await syncImapAccount(env, account);
        break;
      default:
        return c.json({ error: 'Unsupported provider' }, 400);
    }

    return c.json({ success: true, result });
  } catch (error) {
    console.error('Sync error:', error);
    return c.json({ error: 'Sync failed', details: String(error) }, 500);
  }
});

/**
 * Webhook endpoint for Gmail push notifications
 */
app.post('/webhooks/gmail', async (c) => {
  const env = c.env;

  try {
    const body = await c.req.json();
    const { emailAddress, historyId } = decodeGmailPushNotification(body);

    // Find account by email and trigger incremental sync
    const account = await findAccountByEmail(env, emailAddress);
    if (account) {
      await syncGmailAccount(env, account, historyId);
    }

    return c.json({ success: true });
  } catch (error) {
    console.error('Gmail webhook error:', error);
    return c.json({ error: 'Webhook processing failed' }, 500);
  }
});

/**
 * Webhook endpoint for Outlook notifications
 */
app.post('/webhooks/outlook', async (c) => {
  const env = c.env;
  const validationToken = c.req.query('validationToken');

  // Handle validation request
  if (validationToken) {
    return c.text(validationToken);
  }

  try {
    const body = await c.req.json();
    // Process Outlook change notifications
    for (const notification of body.value || []) {
      const accountId = notification.clientState; // We store accountId in clientState
      if (accountId) {
        const account = await fetchAccount(env, accountId);
        if (account) {
          await syncOutlookAccount(env, account);
        }
      }
    }

    return c.json({ success: true });
  } catch (error) {
    console.error('Outlook webhook error:', error);
    return c.json({ error: 'Webhook processing failed' }, 500);
  }
});

// ============================================================================
// Provider-specific sync implementations
// ============================================================================

async function syncGmailAccount(
  env: Env,
  account: EmailAccount,
  fromHistoryId?: string
): Promise<SyncResult> {
  const result: SyncResult = {
    messagesIngested: 0,
    threadsUpdated: 0,
    errors: [],
  };

  try {
    // Refresh token if needed
    const accessToken = await refreshGmailToken(env, account);

    // Determine sync strategy
    const historyId = fromHistoryId || account.historyId;

    if (historyId) {
      // Incremental sync using history API
      const changes = await fetchGmailHistory(accessToken, historyId);

      for (const change of changes.messages) {
        try {
          const message = await fetchGmailMessage(accessToken, change.messageId);
          await ingestMessage(env, account, message);
          result.messagesIngested++;
        } catch (err) {
          result.errors.push(`Failed to fetch message ${change.messageId}: ${err}`);
        }
      }

      result.newHistoryId = changes.historyId;
    } else {
      // Full sync - fetch recent messages
      const messages = await fetchGmailMessageList(accessToken, 100);

      for (const msg of messages) {
        try {
          const fullMessage = await fetchGmailMessage(accessToken, msg.id);
          await ingestMessage(env, account, fullMessage);
          result.messagesIngested++;
        } catch (err) {
          result.errors.push(`Failed to fetch message ${msg.id}: ${err}`);
        }
      }

      result.newHistoryId = messages[0]?.historyId;
    }

    // Update sync state in Convex
    if (result.newHistoryId) {
      await updateSyncState(env, account.id, result.newHistoryId);
    }

  } catch (error) {
    result.errors.push(`Gmail sync error: ${error}`);
  }

  return result;
}

async function syncOutlookAccount(env: Env, account: EmailAccount): Promise<SyncResult> {
  const result: SyncResult = {
    messagesIngested: 0,
    threadsUpdated: 0,
    errors: [],
  };

  try {
    // Refresh token if needed
    const accessToken = await refreshOutlookToken(env, account);

    // Use delta sync if we have a cursor
    const deltaLink = account.cursor;
    const response = await fetchOutlookMessages(accessToken, deltaLink);

    for (const message of response.messages) {
      try {
        const normalized = normalizeOutlookMessage(message);
        await ingestMessage(env, account, normalized);
        result.messagesIngested++;
      } catch (err) {
        result.errors.push(`Failed to process message ${message.id}: ${err}`);
      }
    }

    // Save new delta link
    if (response.deltaLink) {
      await updateSyncState(env, account.id, undefined, response.deltaLink);
    }

  } catch (error) {
    result.errors.push(`Outlook sync error: ${error}`);
  }

  return result;
}

async function syncImapAccount(env: Env, account: EmailAccount): Promise<SyncResult> {
  // IMAP sync is more complex and would require a proper IMAP client
  // This is a placeholder for the implementation
  return {
    messagesIngested: 0,
    threadsUpdated: 0,
    errors: ['IMAP sync not yet implemented'],
  };
}

// ============================================================================
// Gmail API helpers
// ============================================================================

async function refreshGmailToken(env: Env, account: EmailAccount): Promise<string> {
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: env.GOOGLE_CLIENT_ID,
      client_secret: env.GOOGLE_CLIENT_SECRET,
      refresh_token: account.refreshToken,
      grant_type: 'refresh_token',
    }),
  });

  if (!response.ok) {
    throw new Error(`Failed to refresh Gmail token: ${response.status}`);
  }

  const data = await response.json() as { access_token: string };
  return data.access_token;
}

async function fetchGmailHistory(
  accessToken: string,
  startHistoryId: string
): Promise<{ messages: { messageId: string }[]; historyId: string }> {
  const response = await fetch(
    `https://gmail.googleapis.com/gmail/v1/users/me/history?startHistoryId=${startHistoryId}`,
    {
      headers: { Authorization: `Bearer ${accessToken}` },
    }
  );

  if (!response.ok) {
    throw new Error(`Failed to fetch Gmail history: ${response.status}`);
  }

  const data = await response.json() as any;
  const messages: { messageId: string }[] = [];

  for (const history of data.history || []) {
    for (const msg of history.messagesAdded || []) {
      messages.push({ messageId: msg.message.id });
    }
  }

  return {
    messages,
    historyId: data.historyId,
  };
}

async function fetchGmailMessageList(
  accessToken: string,
  maxResults: number
): Promise<{ id: string; historyId: string }[]> {
  const response = await fetch(
    `https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=${maxResults}`,
    {
      headers: { Authorization: `Bearer ${accessToken}` },
    }
  );

  if (!response.ok) {
    throw new Error(`Failed to fetch Gmail message list: ${response.status}`);
  }

  const data = await response.json() as any;
  return data.messages || [];
}

async function fetchGmailMessage(
  accessToken: string,
  messageId: string
): Promise<RawEmailMessage> {
  const response = await fetch(
    `https://gmail.googleapis.com/gmail/v1/users/me/messages/${messageId}?format=full`,
    {
      headers: { Authorization: `Bearer ${accessToken}` },
    }
  );

  if (!response.ok) {
    throw new Error(`Failed to fetch Gmail message: ${response.status}`);
  }

  const data = await response.json() as any;
  return parseGmailMessage(data);
}

function parseGmailMessage(gmailMessage: any): RawEmailMessage {
  const headers = gmailMessage.payload?.headers || [];
  const getHeader = (name: string) =>
    headers.find((h: any) => h.name.toLowerCase() === name.toLowerCase())?.value || '';

  const parseParticipants = (value: string): EmailParticipant[] => {
    if (!value) return [];
    return value.split(',').map((p: string) => {
      const match = p.trim().match(/^(?:"?([^"]*)"?\s*)?<?([^>]+@[^>]+)>?$/);
      if (match) {
        return { name: match[1]?.trim(), email: match[2].trim() };
      }
      return { email: p.trim() };
    });
  };

  const fromParsed = parseParticipants(getHeader('From'))[0] || { email: '' };

  // Extract body
  let bodyText = '';
  let bodyHtml = '';

  const extractBody = (part: any) => {
    if (part.mimeType === 'text/plain' && part.body?.data) {
      bodyText = Buffer.from(part.body.data, 'base64url').toString('utf-8');
    } else if (part.mimeType === 'text/html' && part.body?.data) {
      bodyHtml = Buffer.from(part.body.data, 'base64url').toString('utf-8');
    }

    if (part.parts) {
      part.parts.forEach(extractBody);
    }
  };

  extractBody(gmailMessage.payload);

  // Extract attachments
  const attachments: EmailAttachment[] = [];
  const extractAttachments = (part: any) => {
    if (part.filename && part.body?.attachmentId) {
      attachments.push({
        id: part.body.attachmentId,
        filename: part.filename,
        mimeType: part.mimeType,
        size: part.body.size || 0,
      });
    }
    if (part.parts) {
      part.parts.forEach(extractAttachments);
    }
  };
  extractAttachments(gmailMessage.payload);

  return {
    messageId: gmailMessage.id,
    threadId: gmailMessage.threadId,
    from: fromParsed,
    to: parseParticipants(getHeader('To')),
    cc: parseParticipants(getHeader('Cc')),
    bcc: parseParticipants(getHeader('Bcc')),
    subject: getHeader('Subject'),
    snippet: gmailMessage.snippet || '',
    bodyText,
    bodyHtml,
    internalDate: parseInt(gmailMessage.internalDate, 10),
    labelIds: gmailMessage.labelIds || [],
    attachments,
    headers: Object.fromEntries(headers.map((h: any) => [h.name, h.value])),
  };
}

function decodeGmailPushNotification(body: any): { emailAddress: string; historyId: string } {
  const data = JSON.parse(Buffer.from(body.message.data, 'base64').toString());
  return {
    emailAddress: data.emailAddress,
    historyId: data.historyId,
  };
}

// ============================================================================
// Outlook API helpers
// ============================================================================

async function refreshOutlookToken(env: Env, account: EmailAccount): Promise<string> {
  const response = await fetch('https://login.microsoftonline.com/common/oauth2/v2.0/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: env.OUTLOOK_CLIENT_ID,
      client_secret: env.OUTLOOK_CLIENT_SECRET,
      refresh_token: account.refreshToken,
      grant_type: 'refresh_token',
    }),
  });

  if (!response.ok) {
    throw new Error(`Failed to refresh Outlook token: ${response.status}`);
  }

  const data = await response.json() as { access_token: string };
  return data.access_token;
}

async function fetchOutlookMessages(
  accessToken: string,
  deltaLink?: string
): Promise<{ messages: any[]; deltaLink?: string }> {
  const url = deltaLink ||
    'https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages/delta?$select=id,subject,from,toRecipients,ccRecipients,bccRecipients,body,receivedDateTime,hasAttachments,conversationId';

  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });

  if (!response.ok) {
    throw new Error(`Failed to fetch Outlook messages: ${response.status}`);
  }

  const data = await response.json() as any;

  return {
    messages: data.value || [],
    deltaLink: data['@odata.deltaLink'],
  };
}

function normalizeOutlookMessage(outlookMessage: any): RawEmailMessage {
  const parseRecipient = (r: any): EmailParticipant => ({
    name: r.emailAddress?.name,
    email: r.emailAddress?.address || '',
  });

  return {
    messageId: outlookMessage.id,
    threadId: outlookMessage.conversationId,
    from: parseRecipient(outlookMessage.from),
    to: (outlookMessage.toRecipients || []).map(parseRecipient),
    cc: (outlookMessage.ccRecipients || []).map(parseRecipient),
    bcc: (outlookMessage.bccRecipients || []).map(parseRecipient),
    subject: outlookMessage.subject || '',
    snippet: outlookMessage.bodyPreview || '',
    bodyText: outlookMessage.body?.contentType === 'text' ? outlookMessage.body.content : '',
    bodyHtml: outlookMessage.body?.contentType === 'html' ? outlookMessage.body.content : '',
    internalDate: new Date(outlookMessage.receivedDateTime).getTime(),
    labelIds: [], // Outlook uses folders, mapped separately
    attachments: [], // Would need separate API call
    headers: {},
  };
}

// ============================================================================
// Convex integration
// ============================================================================

async function fetchAccount(env: Env, accountId: string): Promise<EmailAccount | null> {
  const response = await fetch(`${env.CONVEX_URL}/api/query`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${env.CONVEX_DEPLOY_KEY}`,
    },
    body: JSON.stringify({
      path: 'email/queries:getAccountById',
      args: { accountId },
    }),
  });

  if (!response.ok) {
    console.error('Failed to fetch account:', response.status);
    return null;
  }

  const data = await response.json() as any;
  return data.value;
}

async function findAccountByEmail(env: Env, emailAddress: string): Promise<EmailAccount | null> {
  const response = await fetch(`${env.CONVEX_URL}/api/query`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${env.CONVEX_DEPLOY_KEY}`,
    },
    body: JSON.stringify({
      path: 'email/queries:getAccountByEmail',
      args: { emailAddress },
    }),
  });

  if (!response.ok) {
    return null;
  }

  const data = await response.json() as any;
  return data.value;
}

async function ingestMessage(
  env: Env,
  account: EmailAccount,
  message: RawEmailMessage
): Promise<void> {
  const response = await fetch(`${env.CONVEX_URL}/email/ingest/insertBatch`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${env.CONVEX_DEPLOY_KEY}`,
    },
    body: JSON.stringify({
      accountId: account.id,
      userId: account.userId,
      messages: [message],
    }),
  });

  if (!response.ok) {
    throw new Error(`Failed to ingest message: ${response.status}`);
  }
}

async function updateSyncState(
  env: Env,
  accountId: string,
  historyId?: string,
  cursor?: string
): Promise<void> {
  const response = await fetch(`${env.CONVEX_URL}/api/mutation`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${env.CONVEX_DEPLOY_KEY}`,
    },
    body: JSON.stringify({
      path: 'email/mutations:updateSyncState',
      args: { accountId, historyId, cursor },
    }),
  });

  if (!response.ok) {
    console.error('Failed to update sync state:', response.status);
  }
}

// Export for Cloudflare Workers
export default app;

// Scheduled handler for periodic sync
export const scheduled: ExportedHandlerScheduledHandler<Env> = async (event, env, ctx) => {
  console.log('Running scheduled email sync...');

  // Fetch all active accounts and sync them
  const response = await fetch(`${env.CONVEX_URL}/api/query`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${env.CONVEX_DEPLOY_KEY}`,
    },
    body: JSON.stringify({
      path: 'email/queries:getActiveAccounts',
      args: {},
    }),
  });

  if (!response.ok) {
    console.error('Failed to fetch active accounts');
    return;
  }

  const data = await response.json() as any;
  const accounts: EmailAccount[] = data.value || [];

  for (const account of accounts) {
    try {
      switch (account.provider) {
        case 'gmail':
          await syncGmailAccount(env, account);
          break;
        case 'outlook':
          await syncOutlookAccount(env, account);
          break;
        case 'imap':
          await syncImapAccount(env, account);
          break;
      }
    } catch (error) {
      console.error(`Failed to sync account ${account.id}:`, error);
    }
  }
};
