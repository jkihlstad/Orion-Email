import { mutation } from "../_generated/server";
import { v } from "convex/values";

const CalendarEventPayload = v.object({
  payloadVersion: v.string(),
  provider: v.string(),
  accountId: v.string(),
  providerEventId: v.string(),
  providerCalendarId: v.optional(v.string()),
  event: v.object({
    title: v.optional(v.string()),
    location: v.optional(v.string()),
    startAtMs: v.number(),
    endAtMs: v.number(),
    timezone: v.string(),
    allDay: v.optional(v.boolean()),
    attendees: v.optional(v.array(v.object({ email: v.string(), name: v.optional(v.string()) }))),
    organizer: v.optional(v.object({ email: v.string(), name: v.optional(v.string()) })),
    rrule: v.optional(v.string()),
    notesRef: v.optional(v.string()),
  }),
  sync: v.optional(v.object({
    source: v.string(),
    syncToken: v.optional(v.string()),
  })),
});

export const ingestEventsBatch = mutation({
  args: {
    clerkUserId: v.string(),
    events: v.array(v.object({
      eventType: v.string(),
      payload: v.any(),
      idempotencyKey: v.optional(v.string()),
    })),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    const results: { index: number; eventId: string; status: string }[] = [];

    for (let i = 0; i < args.events.length; i++) {
      const { eventType, payload, idempotencyKey } = args.events[i];

      // Check idempotency
      if (idempotencyKey) {
        const existing = await ctx.db
          .query("events")
          .withIndex("by_idempotency", (q) =>
            q.eq("userId", args.clerkUserId).eq("idempotencyKey", idempotencyKey)
          )
          .unique();
        if (existing) {
          results.push({ index: i, eventId: existing._id, status: "duplicate" });
          continue;
        }
      }

      // Lookup registry for brainStatus
      const registry = await ctx.db
        .query("brainEventRegistry")
        .withIndex("by_event_type", (q) => q.eq("eventType", eventType))
        .unique();

      const brainStatus = registry?.defaultBrainStatus ?? "skipped";

      const eventId = await ctx.db.insert("events", {
        userId: args.clerkUserId,
        type: eventType,
        payload,
        timestamp: now,
        brainStatus,
        idempotencyKey,
      });

      // Also upsert into calendarEvents table for query efficiency
      if (eventType === "calendar.event.upserted" && payload?.event) {
        const ev = payload.event;

        // Find calendar account reference
        const account = await ctx.db
          .query("calendarAccounts")
          .withIndex("by_clerk_id_provider", (q) =>
            q.eq("clerkUserId", args.clerkUserId).eq("provider", payload.provider)
          )
          .first();

        if (account) {
          const existing = await ctx.db
            .query("calendarEvents")
            .withIndex("by_account_provider_id", (q) =>
              q.eq("accountId", account._id).eq("providerEventId", payload.providerEventId)
            )
            .unique();

          if (existing) {
            await ctx.db.patch(existing._id, {
              title: ev.title ?? "Untitled",
              location: ev.location,
              startAt: ev.startAtMs,
              endAt: ev.endAtMs,
              timezone: ev.timezone,
              attendees: (ev.attendees ?? []).map((a: any) => ({
                email: a.email,
                name: a.name,
              })),
              organizer: ev.organizer ?? { email: "unknown@example.com" },
              updatedAt: now,
            });
          } else {
            await ctx.db.insert("calendarEvents", {
              clerkUserId: args.clerkUserId,
              accountId: account._id,
              providerEventId: payload.providerEventId,
              title: ev.title ?? "Untitled",
              location: ev.location,
              startAt: ev.startAtMs,
              endAt: ev.endAtMs,
              timezone: ev.timezone,
              attendees: (ev.attendees ?? []).map((a: any) => ({
                email: a.email,
                name: a.name,
              })),
              organizer: ev.organizer ?? { email: "unknown@example.com" },
              visibility: "private",
              policy: {
                lockState: "flexible",
                movePermissions: "userOnly",
                requiresUserConfirmationBeforeSendingRequests: true,
                contentSharing: "minimal",
              },
              updatedAt: now,
            });
          }
        }
      }

      // Handle deletions
      if (eventType === "calendar.event.deleted" && payload?.providerEventId) {
        // Find the account first
        const account = await ctx.db
          .query("calendarAccounts")
          .withIndex("by_clerk_id_provider", (q) =>
            q.eq("clerkUserId", args.clerkUserId).eq("provider", payload.provider)
          )
          .first();

        if (account) {
          const existing = await ctx.db
            .query("calendarEvents")
            .withIndex("by_account_provider_id", (q) =>
              q.eq("accountId", account._id).eq("providerEventId", payload.providerEventId)
            )
            .unique();

          if (existing) {
            await ctx.db.patch(existing._id, { deletedAt: now });
          }
        }
      }

      results.push({ index: i, eventId, status: "created" });
    }

    return { results };
  },
});

export const recordAccountConnected = mutation({
  args: {
    clerkUserId: v.string(),
    provider: v.union(
      v.literal("google"),
      v.literal("outlook"),
      v.literal("apple"),
      v.literal("caldav")
    ),
    primaryEmail: v.optional(v.string()),
    accessLevel: v.string(),
    scopes: v.array(v.string()),
  },
  handler: async (ctx, args) => {
    const now = Date.now();

    // Upsert calendar account
    const existing = await ctx.db
      .query("calendarAccounts")
      .withIndex("by_clerk_id_provider", (q) =>
        q.eq("clerkUserId", args.clerkUserId).eq("provider", args.provider)
      )
      .first();

    let accountId: string;
    if (existing) {
      await ctx.db.patch(existing._id, {
        status: "active",
        primaryEmail: args.primaryEmail ?? existing.primaryEmail,
      });
      accountId = existing._id;
    } else {
      accountId = await ctx.db.insert("calendarAccounts", {
        clerkUserId: args.clerkUserId,
        provider: args.provider,
        status: "active",
        primaryEmail: args.primaryEmail ?? "",
        createdAt: now,
      });
    }

    // Append event
    await ctx.db.insert("events", {
      userId: args.clerkUserId,
      type: "calendar.account.connected",
      payload: {
        payloadVersion: "1",
        provider: args.provider,
        account: {
          accountId,
          primaryEmail: args.primaryEmail,
          scopes: args.scopes,
          accessLevel: args.accessLevel,
        },
      },
      timestamp: now,
      brainStatus: "pending",
    });

    return { accountId };
  },
});
