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
- **Timer widgets** — Home Screen widgets to start a timer (feeding/sleep/tummy time/pumping)
  and to watch the running timer with live elapsed time and a one-tap Stop that logs the
  activity. Lock Screen and StandBy accessories show the running timer at a glance. Widget
  actions push to the server immediately (falling back to the sync queue when offline).
- **Merged timeline** — day-grouped activity feed across all event types, with tap-to-edit,
  swipe-to-delete, and inline colored tag chips on each row. **Search** (notes, tags, type,
  child) and a **type + date-range filter** narrow it instantly, all offline over the cache.
  Sync keeps a rolling 30-day window; **Load older activity** at the foot of the timeline
  pages further back on demand (down to the child's birth) without dropping anything cached.
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
| `BB_START_TAB=timeline\|settings` | Open on a specific tab |
| `BB_OPEN=feeding\|change\|…` | Auto-present a new-entry editor |
| `BB_LOAD_OLDER=<n>` | Auto-page the timeline back `n` history chunks on launch (with `BB_DEMO`) |
| `BB_LOCK=1` | Force the Face ID lock on |
