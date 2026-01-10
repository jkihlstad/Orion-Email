export type TimeRange = { startAt: number; endAt: number };

export function overlaps(a: TimeRange, b: TimeRange) {
  return a.startAt < b.endAt && b.startAt < a.endAt;
}

export function clampWithinWindow(candidate: TimeRange, window: TimeRange) {
  const startAt = Math.max(candidate.startAt, window.startAt);
  const endAt = Math.min(candidate.endAt, window.endAt);
  if (endAt <= startAt) return null;
  return { startAt, endAt };
}

export function findFreeSlots(
  searchWindow: TimeRange,
  busy: TimeRange[],
  durationMinutes: number,
  stepMinutes = 15,
  maxSlots = 3,
): TimeRange[] {
  const step = stepMinutes * 60_000;
  const dur = durationMinutes * 60_000;

  const results: TimeRange[] = [];
  for (let t = searchWindow.startAt; t + dur <= searchWindow.endAt; t += step) {
    const slot = { startAt: t, endAt: t + dur };
    const conflict = busy.some((b) => overlaps(slot, b));
    if (!conflict) {
      results.push(slot);
      if (results.length >= maxSlots) break;
    }
  }
  return results;
}
