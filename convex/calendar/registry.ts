import { mutation, query } from "../_generated/server";
import { v } from "convex/values";

export const seedCalendarRegistry = mutation({
  args: {},
  handler: async (ctx) => {
    const now = Date.now();
    const entries = [
      { eventType: "calendar.account.connected", enabled: true, requireRefs: [], defaultBrainStatus: "pending" as const },
      { eventType: "calendar.account.disconnected", enabled: true, requireRefs: [], defaultBrainStatus: "skipped" as const },
      { eventType: "calendar.sync.started", enabled: true, requireRefs: [], defaultBrainStatus: "skipped" as const },
      { eventType: "calendar.sync.completed", enabled: true, requireRefs: [], defaultBrainStatus: "pending" as const },
      { eventType: "calendar.sync.failed", enabled: true, requireRefs: [], defaultBrainStatus: "skipped" as const },
      { eventType: "calendar.event.upserted", enabled: true, requireRefs: [], defaultBrainStatus: "pending" as const },
      { eventType: "calendar.event.deleted", enabled: true, requireRefs: [], defaultBrainStatus: "pending" as const },
      { eventType: "calendar.event.policy.updated", enabled: true, requireRefs: [], defaultBrainStatus: "pending" as const },
      { eventType: "calendar.reschedule.proposed", enabled: true, requireRefs: [], defaultBrainStatus: "pending" as const },
      { eventType: "calendar.reschedule.requestedApproval", enabled: true, requireRefs: [], defaultBrainStatus: "pending" as const },
      { eventType: "calendar.reschedule.approved", enabled: true, requireRefs: [], defaultBrainStatus: "pending" as const },
      { eventType: "calendar.reschedule.rejected", enabled: true, requireRefs: [], defaultBrainStatus: "skipped" as const },
      { eventType: "calendar.reschedule.applied", enabled: true, requireRefs: [], defaultBrainStatus: "pending" as const },
      { eventType: "calendar.ui.openedEvent", enabled: true, requireRefs: [], defaultBrainStatus: "skipped" as const },
      { eventType: "calendar.ui.dragRescheduled", enabled: true, requireRefs: [], defaultBrainStatus: "pending" as const },
    ];

    for (const entry of entries) {
      const existing = await ctx.db
        .query("brainEventRegistry")
        .withIndex("by_event_type", (q) => q.eq("eventType", entry.eventType))
        .unique();

      if (!existing) {
        await ctx.db.insert("brainEventRegistry", { ...entry, updatedAt: now });
      }
    }
    return { seeded: entries.length };
  },
});

export const listRegistryEntries = query({
  args: { prefix: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const all = await ctx.db.query("brainEventRegistry").collect();
    if (args.prefix) {
      return all.filter((e) => e.eventType.startsWith(args.prefix!));
    }
    return all;
  },
});
