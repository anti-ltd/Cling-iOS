# Cling

**Pin anything to your Dynamic Island.**

Cling is a "hold this thought for me" layer over all of iOS: pin a note, a
countdown, where you parked, a live football/UFC/US-league score, or a stock
ticker, and it stays glanceable in the Dynamic Island and on the lock screen —
across every app — until you dismiss it. Sibling app to [Clink](../Clink-iOS);
same Liquid Glass design family, built on [iUX-ios](../iUX-ios).

- Platform: iOS 17.2+ (Live Activities started from Shortcuts need 17.2)
- Language: Swift 6.0, strict concurrency
- On-device first; an optional Cloudflare Worker pushes live scores/quotes while
  the app is closed (see `server/`)

## Pin types

| Type | What it holds |
|---|---|
| Note | A short text (or shared link/image) you need to keep in view |
| Timer | A countdown with a label |
| Parking | Location + optional photo of the spot |
| Decoration | A glyph that dresses the Dynamic Island |
| Match | A live football score, push-updated while closed |
| Fight | A live UFC card — current bout, round, result |
| Game | A live NBA / NFL / NHL / MLB score |
| Ticker | A live stock or crypto quote |

New pin types are cheap to add — see [ARCHITECTURE.md](ARCHITECTURE.md).

## Building

Prerequisites: Xcode 16+, `xcodegen` (`brew install xcodegen`), and iUX-ios
cloned as a sibling:

```bash
git clone git@github.com:anti-ltd/iUX-ios.git ../iUX-ios
```

```bash
make icon      # render the app icon
make project   # generate Cling.xcodeproj from project.yml
make build     # build for the simulator
make run       # boot the sim, install, launch
make device    # build + install + launch on a paired iPhone
```

Live Activity / Dynamic Island behavior only really shows on a physical
iPhone — use `make device`.

## Targets

- **Cling** — container app: pin list, quick-add, customization, App Intents,
  Live Activity lifecycle.
- **ClingWidgets** — WidgetKit extension hosting the Live Activity.
- **ClingShare** — share extension: pin text/URLs/images from any share sheet.
- **Sources/ClingKit** — shared models + storage, compiled into all three.

## License

Counter-Limitation License (CLL) v1.2 — see [LICENSE.md](LICENSE.md).
