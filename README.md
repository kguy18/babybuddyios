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
- **Dashboard** — last-event cards, active timers, and today's running totals.
- **Merged timeline** — day-grouped activity feed across all event types, with tap-to-edit,
  swipe-to-delete, and inline colored tag chips on each row.
- **Offline-first** — the local SwiftData store is the source of truth; every change is applied
  instantly and queued for delivery. An offline banner shows when the server is unreachable.
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

### Connecting

On first launch, enter your Baby Buddy server URL and the API token from your web
**User → Settings** page.

### Debug launch flags (simulator)

Pass via `SIMCTL_CHILD_<NAME>` env vars to `xcrun simctl launch`:

| Flag | Effect |
|------|--------|
| `BB_DEMO=1` | Seed sample data and skip the network (no server needed) |
| `BB_SEED_CONFLICT=1` | Also seed a sample sync conflict |
| `BB_START_TAB=timeline\|settings` | Open on a specific tab |
| `BB_OPEN=feeding\|change\|…` | Auto-present a new-entry editor |
| `BB_LOCK=1` | Force the Face ID lock on |
