import type { Env } from "./env";

export async function convexFetch<T>(
  env: Env,
  path: string,
  init?: RequestInit,
): Promise<T> {
  const url = `${env.CONVEX_HTTP_BASE}${path}`;
  const res = await fetch(url, {
    ...init,
    headers: {
      "content-type": "application/json",
      ...(init?.headers || {}),
    },
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(`Convex HTTP ${res.status}: ${text}`);
  }
  return (await res.json()) as T;
}
