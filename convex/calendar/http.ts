import { httpAction } from "convex/server";
import { api } from "../_generated/api";
import { verifyClerkJwtOrThrow } from "../auth/verifyClerk";

function json(res: unknown, status = 200) {
  return new Response(JSON.stringify(res), {
    status,
    headers: { "content-type": "application/json" },
  });
}

export const listEvents = httpAction(async (ctx, req) => {
  const auth = await verifyClerkJwtOrThrow(req);
  const { startAt, endAt } = await req.json();
  const events = await ctx.runQuery(api.calendar.queries.listEvents, {
    clerkUserId: auth.clerkUserId,
    startAt,
    endAt,
  });
  return json({ events });
});

export const updatePolicy = httpAction(async (ctx, req) => {
  const auth = await verifyClerkJwtOrThrow(req);
  const body = await req.json();
  await ctx.runMutation(api.calendar.mutations.updateEventPolicy, {
    clerkUserId: auth.clerkUserId,
    eventId: body.eventId,
    policy: body.policy,
  });
  // append audit event
  await ctx.runMutation(api.events.append.appendEvent, {
    clerkUserId: auth.clerkUserId,
    eventType: "calendar.event.policy.updated",
    payload: { eventId: body.eventId, policy: body.policy },
    brainStatus: "pending",
  });
  return json({ ok: true });
});

export const listProposals = httpAction(async (ctx, req) => {
  const auth = await verifyClerkJwtOrThrow(req);
  const url = new URL(req.url);
  const status = url.searchParams.get("status") ?? "sent";
  const proposals = await ctx.runQuery(api.calendar.queries.listProposals, {
    clerkUserId: auth.clerkUserId,
    status,
  });
  return json({ proposals });
});

export const applyProposal = httpAction(async (ctx, req) => {
  const auth = await verifyClerkJwtOrThrow(req);
  const { proposalId } = await req.json();
  await ctx.runMutation(api.calendar.mutations.applyApprovedProposal, {
    clerkUserId: auth.clerkUserId,
    proposalId,
  });
  await ctx.runMutation(api.events.append.appendEvent, {
    clerkUserId: auth.clerkUserId,
    eventType: "calendar.reschedule.applied",
    payload: { proposalId },
    brainStatus: "none",
  });
  return json({ ok: true });
});

export const ingestEvents = httpAction(async (ctx, req) => {
  const auth = await verifyClerkJwtOrThrow(req);
  const { events } = await req.json();
  const result = await ctx.runMutation(api.calendar.ingest.ingestEventsBatch, {
    clerkUserId: auth.clerkUserId,
    events,
  });
  return json(result);
});

export const connectAccount = httpAction(async (ctx, req) => {
  const auth = await verifyClerkJwtOrThrow(req);
  const body = await req.json();
  const result = await ctx.runMutation(api.calendar.ingest.recordAccountConnected, {
    clerkUserId: auth.clerkUserId,
    provider: body.provider,
    primaryEmail: body.primaryEmail,
    accessLevel: body.accessLevel,
    scopes: body.scopes ?? [],
  });
  return json(result);
});
