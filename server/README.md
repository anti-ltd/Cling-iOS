# cling-push

Keeps a pinned World Cup match live in Cling's Dynamic Island **while Cling is
closed**. Polls the public ESPN scoreboard and pushes Live Activity updates to
subscribed devices over APNs.

```
ESPN feed ──poll 20s──▶ MatchPoller (Durable Object)
                          │ diff vs last score, push only on change
                          ▼
                        APNs ──▶ Cling Dynamic Island (app closed)
```

The app (`Sources/Cling/MatchPushUploader.swift`) POSTs `/register` whenever a
match is pinned, sending: the activity's APNs **update token**, the **sourceID**
(ESPN event id), and a **content-state template** built by `ActivityPushContract`.
The server swaps only the score/minute/status fields in that template and
re-pushes — it never reconstructs the pin's appearance.

## Layout

| File | Role |
|------|------|
| `src/index.ts` | Worker entry; routes `POST /register` to the DO |
| `src/poller.ts` | `MatchPoller` DO: subscriptions + alarm poll loop + diff |
| `src/espn.ts` | ESPN scoreboard reader (twin of the app's `MatchFeed.swift`) |
| `src/apns.ts` | ES256 provider-token (JWT) + Live Activity push |

## Deploy

Key ID, Team ID and host are already filled into `wrangler.jsonc` (the
token-based APNs key `L8R4WR557T`, Apple team `8248296AJX` — the same pair the
deployed `Clack-Worker` pushes with). The private key is the only secret:

```sh
cd server
npm install
npm run typecheck        # optional

# the APNs auth key — the same one Clack-Worker uses
wrangler secret put APNS_KEY < ../../private-resources/AuthKey_L8R4WR557T.p8

wrangler deploy
```

Then point `MatchPushUploader.endpoint` (in the app) at the deployed route, e.g.
`https://cling-push.<your-subdomain>.workers.dev/register` or a custom
`cling-push.anti.ltd` route.

## APNs environment — read this before debugging a dead push

The push token's environment is set by the **signing cert**, not the
`aps-environment` entitlement string. A `make device` build is Apple
Development-signed → **sandbox** tokens → push to `api.sandbox.push.apple.com`
(the value already set in `wrangler.jsonc`). A production/prod-key push to a
sandbox token returns `403 BadEnvironmentKeyInToken` and the island never moves.
Flip `APNS_HOST` to `api.push.apple.com` only for TestFlight / App Store builds.
The key `L8R4WR557T` is token-based and Sandbox-scoped enough that Clack pushes
to sandbox with it, so it works here too.

## Gotchas (per docs/PUSH-TO-START.md — verify on device)

- **Date format.** Both the content-state `staleDate` and the app's
  `ActivityPushContract` use ISO-8601 with fractional seconds (`toISOString()`
  matches). If the island shows a wrong/blank stale time, the fallback to test is
  unix seconds.
- **`attributes-type` exactness.** Updates don't send attributes, so this only
  matters once push-to-start (start events) is wired — it must equal
  `ClingActivityAttributes`.
- **Throttling.** APNs budgets Live Activity pushes; the diff (push only on an
  actual score/minute/status change) keeps the rate to roughly one per minute per
  match while live.

## Not wired yet

- **Push-to-start** (island appears at kickoff with Cling never opened). The
  `pushToStart` token already arrives in `/register`; add a `start` event push
  using the uploaded `attributes` template. Today the device starts the activity
  locally and the server only *updates* it.
- **Token upload auth.** `/register` is open. Add a shared secret / Turnstile
  before this is public.
