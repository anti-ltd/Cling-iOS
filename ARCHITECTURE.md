# Cling Architecture

Two things matter here: the **pin-type plugin pattern** (adding a pin type is
one file plus two enum cases), and **honest Live Activity lifetime handling**
inside iOS's hard limits.

## Process topology

Three processes, isolated by iOS, sharing state only through the App Group
`group.ltd.anti.cling`:

```
┌─────────────┐   writes pins/settings   ┌──────────────────────┐
│  Cling app   │ ───────────────────────▶ │  App Group container │
│ (lifecycle   │ ◀─────────────────────── │  cling-pins.v1.json  │
│  owner)      │      Darwin notif        │  cling-settings.v1…  │
└─────────────┘                           │  cling-photos/*.jpg  │
      │  Activity.request / update / end  └──────────────────────┘
      ▼                                           ▲          ▲
┌──────────────┐  renders attrs + state    ┌──────┴─────┐ ┌──┴────────┐
│  ActivityKit  │ ────────────────────────▶ │ClingWidgets │ │ClingShare │
└──────────────┘                            └────────────┘ └───────────┘
```

- `Sources/ClingKit` is a **shared source directory** compiled into all three
  targets (Clink's pattern — no dynamic framework, no rpath/embedding traps).
- `ClingStore` persists JSON **files** in the App Group, never App Group
  `UserDefaults` (cfprefsd caches cross-process reads stale — learned in
  Clink). Darwin notifications fire on save so a running sibling reacts now.
- Photos travel as **filenames** in `PhotoStore`'s shared directory. Activity
  `ContentState` has a ~4KB budget; the widget process shares the container
  and loads bytes itself.

## The pin-type plugin pattern

ActivityKit binds each widget `ActivityConfiguration` to exactly one concrete
`ActivityAttributes` type — you cannot register one per pin type. So
heterogeneity lives in the data, not the configuration:

- **`PinPayload`** — a Codable enum, one case per type, each holding a typed
  payload struct (`NotePayload`, `TimerPayload`, …).
- **`ClingActivityAttributes`** — the single attributes type. `typeID` rides
  in the (immutable) attributes; `payload` + `appearance` + `staleDate` ride
  in `ContentState`, so content *and look* of a live pin update without
  restarting the activity.
- **`PinModule`** — the plugin protocol. One conforming type per pin type
  owns everything type-specific: display name, symbol choices, validation,
  the quick-add form, the list row, and every Live Activity presentation
  (lock screen, expanded leading/center/trailing/bottom, compact, minimal).
  Returns `AnyView` deliberately: the registry is heterogeneous, the trees
  are tiny, and the system re-renders activity views wholesale anyway.
- **`PinRegistry`** — `[PinTypeID: any PinModule.Type]`, the single place a
  type plugs in. The widget's region views and the app's list/composer all
  dispatch through it. Region content is wrapped in real `View` types because
  `View.body` is `@MainActor`, which makes the registry lookup legal under
  strict concurrency.

`PinRenderContext` (pinID + payload + appearance + staleDate) is deliberately
free of ActivityKit types, so the same renderers serve the in-app appearance
editor — the preview *is* the activity view.

### Adding a pin type

1. Add a case to `PinTypeID` and `PinPayload` with its payload struct
   ([PinTypeID.swift](Sources/ClingKit/PinTypeID.swift),
   [PinPayload.swift](Sources/ClingKit/PinPayload.swift)). The compiler now
   walks you through every exhaustive switch.
2. Create `Sources/ClingKit/Types/<Name>Pin.swift`: the `PinModule`
   conformance and all its views, one file.
3. Register it in [PinRegistry.swift](Sources/ClingKit/PinRegistry.swift).
4. Optional: an App Intent in `Sources/Cling/Intents/`, listed in
   `ClingShortcuts`.

No widget, store, or share-extension changes. The composer's type switcher,
the list, the activity renderers, and the appearance editor pick the type up
from the registry.

## Live Activity lifecycle

### Who can start an activity (iOS rules, not ours)

| Path | Can start? | Cling's use |
|---|---|---|
| App in foreground | yes | quick-add, pending sweep, deep links |
| `LiveActivityIntent` (17.2+) | yes, in-process, background OK | all three intents — why the floor is 17.2 |
| Push-to-start token (17.2+) | yes | future `PushActivityTransport` |
| Widget / share extension | **never** | share ext saves `.pending` + hands off |

### The seam

`ActivityTransport` (start/update/end/currentActivityIDs) has one
implementation today, `LocalActivityTransport` — the only file touching
ActivityKit's request APIs. A push transport later changes no callers.

`PinActivityCoordinator` is the transport's only client:

- **Stale dates.** Every start/update sets
  `staleDate = min(pin.endDate ?? ∞, now + 8h − 60s)` — a minute inside the
  system ceiling so we re-arm before iOS acts. The date is mirrored into
  `ContentState` and onto the persisted `Pin`, and surfaced honestly: rows
  wear an `ExpiryBadge`, lock screens caption "Pinned until 21:40" whenever
  the ceiling (not the pin's own end) is what kills it.
- **Reconciliation.** On launch, the store is aligned with
  `Activity.activities`: a pin claiming `.live` with no backing activity
  becomes `.stale` — visible, honest, renewable. State watchers keep this
  true while running.
- **Statuses.** `.pending` (saved, not yet in the island — share-extension
  pins, failed starts), `.live`, `.stale` (aged out, renewable), `.ended`.

### The re-arm strategy

1. **Silent foreground renewal** (the common case): whenever the app becomes
   active, anything within 30 min of staleness — or already stale but still
   wanted — is restarted invisibly (`AppModel.renewExpiringPins`).
2. **The nudge** (the fallback): `RenewalScheduler` books a local
   notification at `staleDate − 15 min` with a "Keep pinned" action. The tap
   foregrounds the app; `NotificationRouter` re-activates the pin and the
   next nudge is scheduled. Toggleable in Settings.
3. **Share-extension hand-off**: the extension saves `.pending`, posts the
   Darwin notification (a running app sweeps instantly), and fires an
   immediate "Saved — tap to pin it" notification for the not-running case.
   The compose UI states the platform rule outright.

Timers shorter than 8h need none of this — `Text(timerInterval:)` renders
ticks client-side, so the activity never consumes update budget; timers
longer than 8h are treated like ambient pins.

### Customization — the app dresses itself in its pins

`PinAppearance` (accent RGBA + optional gradient end stop, SF Symbol, density,
surface style, font design) follows Clink's Codable-struct pattern, decoded
field-by-field so stored pins survive new fields. Per-pin edits flow through
`AppModel.update` → `coordinator.refresh` → the live activity restyles
without restarting (appearance lives in ContentState). Per-type defaults live
in `ClingSettings` and are edited with the same `AppearanceEditor`, previewing
sample payloads through the real renderers.

Where Clink themes the app around the keyboard, Cling themes the app around
the pins — same philosophy, translated to this product's artifact:

- **Hero pin**: the newest live pin's accent drives the app tint and card
  wash (`AppModel.heroPin` / `chromeAccent`).
- **Backdrop mesh**: `AmbientBackdrop(tints:)` blooms every active pin's
  accent; an empty board falls back to a designed two-tone default.
- **Local theming**: the composer wears the selected type's default look;
  detail and editor screens bathe in the pin's own accent (gradient-aware).
- **Font design** applies centrally (widget region wrappers, list rows,
  previews) so modules stay typeface-agnostic.

## Verification

`make project && make build` for the simulator; Live Activity / Dynamic
Island behavior needs a physical device (`make device`). The system caps
(8h/12h) only manifest on-device over real time — the renewal path is
testable by shortening `PinActivityCoordinator.maxActivityWindow` locally.
