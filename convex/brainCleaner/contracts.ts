export interface ConsentProjection {
  calendarContent?: boolean;
  calendarMetadata?: boolean;
  emailContent?: boolean;
  emailMetadata?: boolean;
}

export interface CleanedEventV1 {
  cleanVersion: "1";
  tenant: { clerkUserId: string };
  source: { system: string; provider: string; accountId?: string };
  event: { id: string; type: string; occurredAtMs: number };
  entities: Record<string, any>;
  content: Record<string, any>;
  privacy: { consent: Record<string, boolean>; redactions: string[] };
  features: Record<string, any>;
}
