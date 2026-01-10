import { ConsentProjection } from "./contracts";

export function cleanCalendarEventV1(params: {
  clerkUserId: string;
  convexEventId: string;
  eventType: string;
  occurredAtMs: number;
  payload: any;
  consentScopes: any;
}) {
  const { clerkUserId, convexEventId, eventType, occurredAtMs, payload } = params;

  const provider = payload?.provider ?? "unknown";
  const accountId = payload?.accountId ?? undefined;
  const providerEventId = payload?.providerEventId ?? payload?.event?.providerEventId ?? convexEventId;
  const providerCalendarId = payload?.providerCalendarId ?? payload?.event?.providerCalendarId ?? undefined;

  const ev = payload?.event ?? {};
  const title = ev?.title ?? undefined;
  const startAtMs = ev?.startAtMs ?? undefined;
  const endAtMs = ev?.endAtMs ?? undefined;
  const tz = ev?.timezone ?? "UTC";

  const consent = {
    calendarMetadata: true,
    calendarContent: true,
  };

  const redactions: string[] = [];
  const content = consent.calendarContent
    ? { title, time: { startAtMs, endAtMs, tz }, location: ev?.location, rrule: ev?.rrule ?? null }
    : (() => {
        redactions.push("calendarContentRemoved");
        return { time: { startAtMs, endAtMs, tz } };
      })();

  return {
    cleanVersion: "1" as const,
    tenant: { clerkUserId },
    source: { system: "calendar", provider, accountId },
    event: { id: providerEventId, type: eventType, occurredAtMs },
    entities: {
      calendarId: providerCalendarId,
      eventId: providerEventId,
      participants: {
        organizerEmail: ev?.organizer?.email,
        attendeeEmails: Array.isArray(ev?.attendees) ? ev.attendees.map((a: any) => a.email).filter(Boolean) : [],
      },
    },
    content,
    privacy: { consent, redactions },
    features: { allDay: !!ev?.allDay, isRecurring: !!ev?.rrule },
  };
}
