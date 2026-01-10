import { Hono } from "hono";
import type { Env } from "../env";
import { convexFetch } from "../convexClient";

export const approveRoute = new Hono<{ Bindings: Env }>();

approveRoute.get("/approve", async (c) => {
  const token = c.req.query("token");
  const decision = c.req.query("decision") ?? "approved";
  const option = Number(c.req.query("option") ?? "0");

  if (!token) return c.text("Missing token", 400);

  const proposalId = token;

  await convexFetch(c.env, "/api/calendar/proposals/recordApprovalDev", {
    method: "POST",
    body: JSON.stringify({
      proposalId,
      decision,
      chosenOptionIndex: option,
      actor: { source: "external_link" },
    }),
  });

  return c.html(`
    <html><body style="font-family: -apple-system, sans-serif; padding: 20px;">
      <h2>Thanks — response recorded.</h2>
      <p>You can close this tab.</p>
    </body></html>
  `);
});
