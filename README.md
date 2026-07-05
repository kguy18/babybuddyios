# Baby Buddy for iOS

A native SwiftUI client for the self-hosted [Baby Buddy](https://github.com/babybuddy/babybuddy)
baby-tracking server. Offline-first, with conflict-aware sync and optional Face ID lock.

## Features

- **Feature parity tracking** — feedings, diaper changes, sleep, tummy time, pumping, notes,
  medications, and measurements (weight, height, head circumference, temperature, BMI), with tags
  and multiple children.
- **Tag chip picker** — add tags as removable colored chips with live autocomplete over the
  server's existing tags (cached for offline use), or create a new tag inline. Chip colors and
  text contrast match the Baby Buddy web app.
- **Dashboard** — last-event cards, active timers, and today's running totals. Each "Today" tile
  (feedings/sleep/diapers/tummy time) taps through to a scoped timeline of just that activity for
  the day, and each "Latest" card taps to open the editor for that entry. The "+" button fans up a
  quick-action stack — Start timer plus the everyday record types — over a "More…" row that opens
  the full activity picker (every log + measurement as a tinted glyph tile). Start a timer for a
  specific activity (feeding/sleep/tummy time/pumping) and stopping it files straight to that
  record — no "convert to…?" step — or start an uncategorized timer.
- **Trends** — a Charts-powered analytics tab, scoped to the selected child over a 7 / 14 / 30-day
  window: daily **sleep** hours, **feedings** per day (plus a total-amount-in-ml sub-chart when
  amounts are recorded), and **diaper changes** per day split into wet vs solid. All aggregated
  from the local cache — no extra network — and each chart falls back to a placeholder when the
  window has no data.
- **Timer widgets** — Home Screen widgets to start a timer (feeding/sleep/tummy time/pumping)
  and to watch the running timer with live elapsed time and a one-tap Stop that logs the
  activity. Lock Screen and StandBy accessories show the running timer at a glance. Widget
  actions push to the server immediately (falling back to the sync queue when offline).
- **Status widget** — an at-a-glance Home Screen widget (small/medium) for the selected child:
  when they last **fed / slept / were changed** (live relative times) plus **today's counts**.
  Lock Screen / StandBy accessories condense it further (inline "Fed 2h ago", circular, and a
  three-line rectangular). Read-only from the local cache — no network — and it tracks the same
  child the dashboard is focused on.
- **Live Activity & Dynamic Island** — a running timer also appears as a Live Activity on the
  Lock Screen and in the Dynamic Island, headed with the child and activity ("Patrick · Sleep"),
  with self-ticking elapsed time and the activity's tint. Stop mirrors the widget: sleep/tummy log
  in one tap, feeding/pumping open the pre-filled form. The app starts and ends the activity as
  timers start/stop in-app, and reconciles it whenever it becomes active — so a timer started or
  stopped from the widget or Siri (whose intents run in the extension process, where ActivityKit
  can't be driven) syncs the banner on the next foreground. Toggle it under **Settings →
  Notifications → Live Activity**.
- **Merged timeline** — day-grouped activity feed across all event types, with tap-to-edit,
  swipe-to-delete, and inline colored tag chips on each row. **Search** (notes, tags, type,
  child) and a **type + date-range filter** narrow it instantly, all offline over the cache.
  Sync keeps a rolling 30-day window; **Load older activity** at the foot of the timeline
  pages further back on demand (down to the child's birth) without dropping anything cached.
- **Photos** — a child's profile picture is shown as the avatar in the dashboard and child
  switcher, and a note's attached image appears as a thumbnail in the timeline and inside the
  note editor. Images are fetched with same-origin auth (cleartext `http` upgraded to `https`)
  and cached on disk. Pick a note image (in the note editor) or a child photo (tap the avatar in
  Settings) straight from your library; the picked image shows instantly and uploads as a
  `multipart/form-data` PATCH. Uploads are **offline-safe** — the bytes are held on disk and the
  photo is sent once the record exists on the server, so a photo added on a plane lands when you
  reconnect.
- **Offline-first** — the local SwiftData store is the source of truth; every change is applied
  instantly and queued for delivery. An offline banner shows when the server is unreachable.
  Settings' **Pending changes** row opens the queue: each waiting write is listed (added / edited /
  deleted), and swiping discards one — reverting the cached record to the server's last-known state.
- **Conflict-aware sync** — because Baby Buddy exposes no server-side change marker, edits are
  diffed against a base snapshot of the record they were derived from. Concurrent server changes
  raise a conflict you resolve with **Keep Mine / Keep Server / field-by-field Merge**.
- **Security** — server URL + API token stored in the Keychain; optional Face ID / passcode lock.

## Architecture

```
SwiftUI Views ─► @Query (SwiftData)        ← local source of truth
        │                ▲
        ▼                │
  LocalRepository ──► LocalEntity / PendingMutation / ConflictRecord
                         │
                    SyncEngine  (pull + push + conflict detection)
                         │
                    APIClient ─► Baby Buddy REST API
```

All 14 record types share a single generic `LocalEntity` envelope (kind + raw JSON payload +
denormalized timestamp/child + sync state + base snapshot), which keeps the timeline, sync engine,
and conflict diff uniform. See `Sources/Persistence`, `Sources/Networking`, `Sources/Sync`.

## Build & run

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
xcodebuild -project BabyBuddy.xcodeproj -scheme BabyBuddy \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build
```

Run the tests with `test` instead of `build`.

### Analytics (optional)

The app integrates [TelemetryDeck](https://telemetrydeck.com), a privacy-focused,
cookieless analytics service. **It is disabled by default and this repository ships
without an App ID**, so builds you make from a clone send no data anywhere.

Analytics only run when a TelemetryDeck App ID is configured at build time:

```sh
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
# then edit Config/Secrets.xcconfig and set TELEMETRYDECK_APP_ID = <your-app-id>
```

`Config/Secrets.xcconfig` is gitignored and must never be committed. The ID flows
into the app's `TelemetryDeckAppID` Info.plist key (see `Config/BabyBuddy.xcconfig`)
and `Analytics.start()` initializes the SDK only when that value is non-empty.
Analytics are also skipped automatically in `BB_DEMO` mode.

### In-app purchases (optional)

The app integrates the [RevenueCat](https://www.revenuecat.com) SDK for managing
subscriptions. Like analytics, **it is disabled by default and this repository ships
without an API key**, so clone builds never reach the purchase backend. Configure it
the same way — in the same gitignored `Config/Secrets.xcconfig`:

```sh
# in Config/Secrets.xcconfig
REVENUECAT_API_KEY = <your-revenuecat-public-apple-sdk-key>   # begins with appl_
```

The key flows into the `RevenueCatAPIKey` Info.plist key, and `Subscriptions.start()`
configures RevenueCat only when it's non-empty (and never in `BB_DEMO`). Entitlement
state is exposed app-wide via the `Subscriptions` observable (`isSubscribed`); no
paywall or feature gating is wired up yet.

### Connecting

On first launch you can sign in two ways:

- **Scan a QR code** (fastest) — on your Baby Buddy site open **User → Add a Device**
  and tap **Scan QR Code** in the app. The QR encodes both your server URL and API key,
  so the connection is filled in and validated automatically — no copy/paste, and it
  works for any self-hosted domain.
- **Enter manually** — type your server URL and the API token from your web
  **User → Settings** page.

### Debug launch flags (simulator)

Pass via `SIMCTL_CHILD_<NAME>` env vars to `xcrun simctl launch`:

| Flag | Effect |
|------|--------|
| `BB_DEMO=1` | Seed sample data and skip the network (no server needed) |
| `BB_SEED_CONFLICT=1` | Also seed a sample sync conflict |
| `BB_START_TAB=timeline\|trends\|settings` | Open on a specific tab |
| `BB_OPEN=feeding\|change\|…` | Auto-present a new-entry editor |
| `BB_LOAD_OLDER=<n>` | Auto-page the timeline back `n` history chunks on launch (with `BB_DEMO`) |
| `BB_LOCK=1` | Force the Face ID lock on |

## Acknowledgements

Baby Buddy for iOS is an unofficial client for the open-source
[Baby Buddy](https://github.com/babybuddy/babybuddy) baby-tracking server, and is
not affiliated with that project. The app's activity glyphs are extracted from
Baby Buddy's Fontello icon font (Font Awesome, MFG Labs, Entypo — all under the
SIL Open Font License 1.1). Full third-party license notices are in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), and are also reproduced in-app
under **Settings → Acknowledgements**.
