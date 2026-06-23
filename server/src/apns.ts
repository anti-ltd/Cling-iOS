/**
 * APNs over HTTP/2 from a Worker: a cached ES256 provider-token (JWT) and a
 * single `pushLiveActivity` that sends one Live Activity `update` to a device's
 * activity update-token.
 *
 * The content-state we send is the app-built template with only the score
 * fields swapped — see `poller.ts`. We never reconstruct `PinAppearance` here;
 * it rides in the template the device uploaded.
 */
import type { Env } from "./index";

// Provider tokens are valid up to 60 min and APNs rejects reuse under ~20 min
// apart; mint a fresh one every ~50 min.
let cached: { jwt: string; mintedAt: number } | null = null;

export async function providerToken(env: Env, nowMs: number): Promise<string> {
  if (cached && nowMs - cached.mintedAt < 50 * 60 * 1000) return cached.jwt;

  const header = b64url(JSON.stringify({ alg: "ES256", kid: env.APNS_KEY_ID }));
  const claims = b64url(
    JSON.stringify({ iss: env.APNS_TEAM_ID, iat: Math.floor(nowMs / 1000) }),
  );
  const signingInput = `${header}.${claims}`;

  const key = await importKey(env.APNS_KEY);
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  const jwt = `${signingInput}.${b64urlBytes(new Uint8Array(sig))}`;
  cached = { jwt, mintedAt: nowMs };
  return jwt;
}

export interface PushResult {
  ok: boolean;
  status: number;
  reason?: string;
}

export interface Alert {
  title: string;
  body: string;
  /** Suppress the sound + haptic — a silent banner that still expands the
   * Dynamic Island. Used for frequent commentary auto-expands. */
  silent?: boolean;
}

export async function pushLiveActivity(
  env: Env,
  updateToken: string,
  topic: string,
  contentState: unknown,
  nowMs: number,
  alert?: Alert,
  staleSeconds = 4 * 3600,
  hostOverride?: string,
): Promise<PushResult> {
  // A device's token is valid on exactly one host: sandbox for a development
  // build (aps-environment=development), production for TestFlight/App Store.
  // The poller retries the other host on BadDeviceToken (see `pushDevice`), so a
  // mixed dev+prod fleet works regardless of which host `APNS_HOST` prefers.
  const host = hostOverride ?? env.APNS_HOST ?? "api.push.apple.com";
  const nowSec = Math.floor(nowMs / 1000);
  const jwt = await providerToken(env, nowMs);

  // An `alert` turns the silent activity update into a banner + sound on the
  // lock screen — the "GOAL!" notification — while still refreshing the island.
  const aps: Record<string, unknown> = {
    timestamp: nowSec,
    event: "update",
    "content-state": contentState,
    "stale-date": nowSec + staleSeconds,
    "relevance-score": 100,
  };
  // A bare title/body shows a silent banner; `sound` (a sibling of `alert` in
  // the aps dict, not nested) makes a goal actually ping the lock screen. The
  // default sound is enough — no custom asset bundled into the extension.
  if (alert) {
    aps.alert = { title: alert.title, body: alert.body };
    // A silent commentary expand omits the sound; goals/full-time still ping.
    if (!alert.silent) aps.sound = "default";
  }
  const body = { aps };

  // Live Activity push budget: priority 10 ("deliver now, wake the device") is
  // what the system meters and, once over budget, throttles — delaying updates
  // and drawing its own spinner over the score. Reserve 10 for the moments that
  // matter (a goal, full time — anything carrying an `alert`); send routine
  // ticks (the minute advancing) at priority 5, which the system delivers
  // best-effort and does NOT bill against the high-priority budget. This is the
  // single biggest lever for a smooth closed-app activity.
  const priority = alert ? "10" : "5";

  const res = await fetch(`https://${host}/3/device/${updateToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-push-type": "liveactivity",
      "apns-topic": topic,
      "apns-priority": priority,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (res.ok) return { ok: true, status: res.status };
  let reason: string | undefined;
  try {
    reason = ((await res.json()) as { reason?: string }).reason;
  } catch {
    reason = await res.text();
  }
  return { ok: false, status: res.status, reason };
}

// MARK: crypto helpers

async function importKey(pem: string): Promise<CryptoKey> {
  const der = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  const bytes = Uint8Array.from(atob(der), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    bytes,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

function b64url(str: string): string {
  return b64urlBytes(new TextEncoder().encode(str));
}

function b64urlBytes(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
