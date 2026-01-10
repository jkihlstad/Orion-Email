import { httpRouter } from "convex/server";
import * as CalendarHttp from "./calendar/http";

const http = httpRouter();

http.route({
  path: "/calendar/events/list",
  method: "POST",
  handler: CalendarHttp.listEvents,
});

http.route({
  path: "/calendar/events/updatePolicy",
  method: "POST",
  handler: CalendarHttp.updatePolicy,
});

http.route({
  path: "/calendar/proposals/list",
  method: "GET",
  handler: CalendarHttp.listProposals,
});

http.route({
  path: "/calendar/proposals/apply",
  method: "POST",
  handler: CalendarHttp.applyProposal,
});

http.route({
  path: "/calendar/events/ingest",
  method: "POST",
  handler: CalendarHttp.ingestEvents,
});

http.route({
  path: "/calendar/accounts/connect",
  method: "POST",
  handler: CalendarHttp.connectAccount,
});

export default http;
