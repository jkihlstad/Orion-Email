import type { TimeRange } from "./heuristics";
import { findFreeSlots } from "./heuristics";

export type CalendarEvent = {
  _id: string;
  startAt: number;
  endAt: number;
  title?: string;
  policy?: any;
  attendees?: any[];
  organizer?: any;
  visibility?: string;
};

export type ProposalOption = {
  startAt: number;
  endAt: number;
  score: number;
  explain: string;
};

export function shouldMoveEvent(ev: CalendarEvent): boolean {
  const state = ev.policy?.lockState ?? "flexible";
  return state === "flexible" || state === "negotiable";
}

export function proposeReschedule(
  ev: CalendarEvent,
  busy: TimeRange[],
  searchWindow: TimeRange,
): { rationale: string; options: ProposalOption[] } {
  const durationMinutes = Math.max(15, Math.round((ev.endAt - ev.startAt) / 60_000));
  const slots = findFreeSlots(searchWindow, busy, durationMinutes, 15, 3);

  const options: ProposalOption[] = slots.map((s, i) => ({
    startAt: s.startAt,
    endAt: s.endAt,
    score: 100 - i * 5,
    explain: "Selected to avoid conflicts and preserve focus windows when possible.",
  }));

  const rationale =
    "This event conflicts with your current plan. Proposed alternatives minimize overlap and keep your day feasible.";

  return { rationale, options };
}
