import { Hono } from "hono";
import type { Env } from "./env";
import { approveRoute } from "./routes/approve";
import { cronRoute } from "./routes/cron";
import { googleOAuthRoute } from "./routes/google-oauth";
import { googleSyncRoute } from "./routes/google-sync";

const app = new Hono<{ Bindings: Env }>();

app.get("/health", (c) => c.json({ ok: true }));
app.route("/", approveRoute);
app.route("/", cronRoute);
app.route("/", googleOAuthRoute);
app.route("/", googleSyncRoute);

export default app;
