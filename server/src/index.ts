/**
 * cling-push — entry Worker.
 *
 * One job: accept a device's roster registration (its one Live Activity token,
 * content-state template, and tracked sport/ticker elements) and hand it to the
 * singleton `MatchPoller` Durable Object, which runs the poll-and-push loop.
 * Everything stateful (the ESPN poll loop, the APNs sends, the diffing) lives in
 * the DO so there's exactly one poller regardless of how many devices register.
 */
import { MatchPoller } from "./poller";

export { MatchPoller };

export interface Env {
  POLLER: DurableObjectNamespace;
  APNS_KEY: string;
  APNS_KEY_ID: string;
  APNS_TEAM_ID: string;
  APNS_HOST?: string;
  // Market quotes (optional — tickers resolve only when set).
  FINNHUB_KEY?: string;        // Finnhub, stock + crypto quotes
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);

    if (url.pathname === "/" || url.pathname === "/health") {
      return new Response("cling-push ok\n");
    }

    if (url.pathname === "/register" && req.method === "POST") {
      // Forward verbatim to the one poller instance.
      const id = env.POLLER.idFromName("singleton");
      return env.POLLER.get(id).fetch(req);
    }

    return new Response("not found", { status: 404 });
  },
};
