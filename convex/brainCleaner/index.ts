import { cleanCalendarEventV1 } from "./calendar";

export function cleanEventV1(params: {
  clerkUserId: string;
  convexEventId: string;
  eventType: string;
  occurredAtMs: number;
  payload: any;
  consentScopes: any;
}) {
  const { eventType } = params;

  if (eventType.startsWith("calendar.")) {
    return cleanCalendarEventV1(params);
  }

  // Default passthrough for unknown event types
  return {
    cleanVersion: "1" as const,
    tenant: { clerkUserId: params.clerkUserId },
    source: { system: "unknown", provider: "unknown" },
    event: { id: params.convexEventId, type: eventType, occurredAtMs: params.occurredAtMs },
    entities: {},
    content: params.payload,
    privacy: { consent: {}, redactions: [] },
    features: {},
  };
}

export { cleanCalendarEventV1 } from "./calendar";
