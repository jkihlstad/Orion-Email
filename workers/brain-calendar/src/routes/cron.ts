import { Hono } from "hono";
import type { Env } from "../env";
import { convexFetch } from "../convexClient";
import { proposeReschedule, shouldMoveEvent } from "../scheduler/planner";

export const cronRoute = new Hono<{ Bindings: Env }>();

cronRoute.get("/cron/run", async (c) => {
  const clerkUserId = c.req.query("user");
  if (!clerkUserId) return c.json({ ok: false, error: "Missing user" }, 400);

  const now = Date.now();
  const horizonEnd = now + 7 * 24 * 60 * 60_000;

  const { events } = await convexFetch<{ events: any[] }>(c.env, "/calendar/events/list", {
    method: "POST",
    headers: {
      authorization: `Bearer dev:${clerkUserId}:admin`,
    },
    body: JSON.stringify({ startAt: now, endAt: horizonEnd }),
  });

  const busy = events.map((e) => ({ startAt: e.startAt, endAt: e.endAt }));
  const searchWindow = { startAt: now + 60 * 60_000, endAt: horizonEnd };

  for (const ev of events) {
    if (!shouldMoveEvent(ev)) continue;
    const state = ev.policy?.lockState ?? "flexible";

    const { rationale, options } = proposeReschedule(ev, busy, searchWindow);

    const requiresApprover = state === "negotiable";
    await convexFetch(c.env, "/api/calendar/proposals/createDev", {
      method: "POST",
      headers: { authorization: `Bearer dev:${clerkUserId}:admin` },
      body: JSON.stringify({
        clerkUserId,
        eventId: ev._id,
        createdBy: "brain",
        rationale,
        options,
        requiresApprover,
        approver: ev.policy?.approver,
      }),
    });
  }

  return c.json({ ok: true, proposalsCreated: true });
});
