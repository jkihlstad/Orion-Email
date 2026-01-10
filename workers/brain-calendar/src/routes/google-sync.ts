import { Hono } from "hono";
import type { Env } from "../env";
import { convexFetch } from "../convexClient";
import { refreshAccessToken } from "./google-oauth";

export const googleSyncRoute = new Hono<{ Bindings: Env }>();

const GOOGLE_CALENDAR_API = "https://www.googleapis.com/calendar/v3";

interface GoogleEvent {
  id: string;
  summary?: string;
  location?: string;
  start: { dateTime?: string; date?: string; timeZone?: string };
  end: { dateTime?: string; date?: string; timeZone?: string };
  attendees?: Array<{ email: string; displayName?: string }>;
  organizer?: { email: string; displayName?: string };
  recurrence?: string[];
  status: string;
}

// Sync events from Google Calendar
googleSyncRoute.get("/sync/google/run", async (c) => {
  const clerkUserId = c.req.query("user");
  if (!clerkUserId) {
    return c.json({ error: "Missing user parameter" }, 400);
  }

  const accessToken = await refreshAccessToken(c.env, clerkUserId);
  if (!accessToken) {
    return c.json({ error: "No valid Google credentials" }, 401);
  }

  // Get primary calendar events
  const now = new Date();
  const timeMin = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000).toISOString(); // 30 days ago
  const timeMax = new Date(now.getTime() + 180 * 24 * 60 * 60 * 1000).toISOString(); // 180 days ahead

  const params = new URLSearchParams({
    timeMin,
    timeMax,
    singleEvents: "true",
    orderBy: "startTime",
    maxResults: "250",
  });

  const response = await fetch(
    `${GOOGLE_CALENDAR_API}/calendars/primary/events?${params}`,
    { headers: { Authorization: `Bearer ${accessToken}` } }
  );

  if (!response.ok) {
    const err = await response.text();
    console.error("Google Calendar API error:", err);
    return c.json({ error: "Failed to fetch events" }, 500);
  }

  const data = await response.json() as { items: GoogleEvent[] };
  const events = data.items || [];

  // Transform to canonical format and ingest
  const canonicalEvents = events
    .filter((e) => e.status !== "cancelled")
    .map((e) => {
      const startAtMs = e.start.dateTime
        ? new Date(e.start.dateTime).getTime()
        : new Date(e.start.date + "T00:00:00").getTime();
      const endAtMs = e.end.dateTime
        ? new Date(e.end.dateTime).getTime()
        : new Date(e.end.date + "T23:59:59").getTime();

      return {
        eventType: "calendar.event.upserted",
        payload: {
          payloadVersion: "1",
          provider: "google",
          accountId: clerkUserId,
          providerEventId: e.id,
          providerCalendarId: "primary",
          event: {
            title: e.summary,
            location: e.location,
            startAtMs,
            endAtMs,
            timezone: e.start.timeZone || "UTC",
            allDay: !e.start.dateTime,
            attendees: e.attendees?.map((a) => ({ email: a.email, name: a.displayName })),
            organizer: e.organizer ? { email: e.organizer.email, name: e.organizer.displayName } : undefined,
            rrule: e.recurrence?.[0],
          },
          sync: { source: "provider" },
        },
        idempotencyKey: `google:${e.id}:${e.start.dateTime || e.start.date}`,
      };
    });

  // Batch ingest to Convex
  if (canonicalEvents.length > 0) {
    await convexFetch(c.env, "/calendar/events/ingest", {
      method: "POST",
      headers: { Authorization: `Bearer dev:${clerkUserId}:user` },
      body: JSON.stringify({ events: canonicalEvents }),
    });
  }

  // Record sync completed
  await convexFetch(c.env, "/calendar/events/ingest", {
    method: "POST",
    headers: { Authorization: `Bearer dev:${clerkUserId}:user` },
    body: JSON.stringify({
      events: [{
        eventType: "calendar.sync.completed",
        payload: {
          payloadVersion: "1",
          provider: "google",
          accountId: clerkUserId,
          eventsProcessed: canonicalEvents.length,
          syncedAtMs: Date.now(),
        },
      }],
    }),
  });

  return c.json({
    ok: true,
    synced: canonicalEvents.length,
    provider: "google"
  });
});

// Disconnect Google Calendar
googleSyncRoute.post("/sync/google/disconnect", async (c) => {
  const clerkUserId = c.req.query("user");
  if (!clerkUserId) {
    return c.json({ error: "Missing user parameter" }, 400);
  }

  // Remove tokens
  await c.env.OAUTH_TOKENS.delete(`google_tokens:${clerkUserId}`);

  return c.json({ ok: true, disconnected: true });
});
