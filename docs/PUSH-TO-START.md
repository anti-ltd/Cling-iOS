# Background pinning — ActivityKit push-to-start

How another app (Clink) makes a pin appear in Cling's Dynamic Island / lock
screen **without Cling being open**. This is the only iOS mechanism that starts
a Live Activity while the target app is not running.

```
Clink ──▶ anti.ltd Worker ──▶ APNs ──▶ iOS starts Cling's Live Activity
          (has the token)     (push)    (Cling stays closed)
```

The `cling://create/…` URL scheme (see `ClingCreateRequest`) is the other,
zero-infra path — but it foregrounds Cling. Use push-to-start when the pin must
appear silently.

## Pieces

| Side | What | Where |
|------|------|-------|
| Cling | mints tokens, parks them | `PushToStartRegistrar` → `PushTokenStore` (`cling-push.v1.json` in the App Group) |
| Cling | entitlement | `aps-environment` in `project.yml` (dev → production for App Store) |
| Server | holds tokens, sends APNs | the anti.ltd Worker (TODO) |
| Wire | strings + JSON shape | `ActivityPushContract` |

## Tokens

`PushTokenStore` holds two kinds (both hex):

- **`pushToStart`** — one per install. Push to it with `event: "start"` to
  create a new activity. Minted only after Cling has launched once; can rotate.
- **`updateTokens[pinID]`** — one per running activity. Push with
  `event: "update"` / `"end"` to change or dismiss that activity.

The Worker must collect these from the device (upload step is the open TODO —
wire `PushToStartRegistrar.onTokensChanged` to POST them).

## APNs request — start a pin

**Headers**

```
:method            POST
:path              /3/device/<pushToStart-token>
apns-push-type     liveactivity
apns-topic         ltd.anti.cling.push-type.liveactivity
apns-priority      10
authorization      bearer <APNs JWT>          # reuse the anti.ltd / ASCManager key
```

`apns-topic` and `apns-push-type` are fixed — see `ActivityPushContract`.

**Body**

```jsonc
{
  "aps": {
    "timestamp": 1750000000,              // unix seconds, now
    "event": "start",
    "attributes-type": "ClingActivityAttributes",
    "attributes":   { /* see below */ },  // start only
    "content-state":{ /* see below */ },
    "stale-date": 1750028800,             // unix seconds
    "relevance-score": 100,
    "alert": {                            // optional banner when it starts
      "title": "Pinned",
      "body": "Pick up milk"
    }
  }
}
```

For `event: "update"` / `"end"`, push to the pin's **update token**, drop
`attributes` / `attributes-type`, keep `content-state`.

## The JSON shapes (`attributes` + `content-state`)

These mirror Swift's `Codable` synthesis of `ClingActivityAttributes` and its
`ContentState`. **Do not hand-guess them** — `ActivityPushContract` emits the
exact bytes:

```swift
ActivityPushContract.referenceAttributesJSON(for: pin)
ActivityPushContract.referenceContentStateJSON(for: pin, staleDate: date)
```

Print those for a sample pin and mirror the output in the Worker. Reference
shape (a note pin):

```jsonc
// attributes
{ "pinID": "F1E2…UUID", "typeID": "note" }

// content-state
{
  "payload": { "note": { "_0": { "text": "Pick up milk" } } },
  "appearance": { /* PinAppearance fields */ },
  "staleDate": "2026-06-17T21:40:00.000Z"
}
```

Note the enum nesting: `PinPayload.note(NotePayload)` encodes as
`{"note":{"_0":{…}}}`; timer → `{"timer":{"_0":{…}}}` with `startDate`/`endDate`;
parking → `{"parking":{"_0":{…}}}`. This is the stored wire format and is
**add-only** — never rename a key.

## ⚠ Must verify on device

Two things can't be checked without a real device (per the no-simulator-build
rule) and **will silently drop the push if wrong**:

1. **Date format in `content-state`.** Apple does not publicly pin ActivityKit's
   content-state date strategy. `ActivityPushContract` uses **ISO-8601** for both
   the reference encoder and what the Worker should send — internally consistent,
   but confirm a real push renders correct dates (timer countdown, stale time)
   before shipping. If ISO-8601 fails, the fallback to test is unix seconds.
2. **`attributes-type` exactness** — must equal `ClingActivityAttributes`.

Also confirm the user has granted Live Activities (`areActivitiesEnabled`) and,
for push-to-start specifically, that frequent pushes aren't being throttled by
the system budget.

## Content budget

The whole payload rides APNs' 4KB Live Activity limit. Text/timer/parking pins
fit easily. **Photos do not travel** — `photoFilename` points into Cling's App
Group container, which a server can't populate, so a pushed pin's photo won't
resolve. Background-pin photo pins need a different mechanism (skip for v1).
