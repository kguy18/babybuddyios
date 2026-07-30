# Architecture

Baby Buddy Companion is offline-first: the local store is the source of truth, and the server is
something the app reconciles with in the background. Nothing in the UI waits on the network.

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

Source lives in `Sources/Persistence`, `Sources/Networking` and `Sources/Sync`.

## One envelope for every record type

All 14 record types share a single generic `LocalEntity` envelope:

- `kind` — which record type this is
- raw JSON payload
- denormalized timestamp and child (so the timeline can sort and filter without decoding)
- sync state
- base snapshot (see conflicts, below)

Keeping every type in one envelope is what lets the merged timeline, the sync engine and the
conflict diff stay uniform instead of growing a branch per record type.

## Offline-first writes

Every change is applied to the local store immediately and queued for delivery as a
`PendingMutation`. An offline banner appears when the server is unreachable.

Settings' **Pending changes** row opens the queue: each waiting write is listed as added, edited
or deleted, and swiping discards one — reverting the cached record to the server's last-known
state.

Photo uploads follow the same path. The bytes are held on disk and the image is sent once the
record exists on the server, so a photo added on a plane lands when you reconnect.

## Conflict-aware sync

Baby Buddy exposes no server-side change marker — no ETag, no `updated_at` the API will filter
on. So the app cannot ask "what changed since I last looked?"

Instead, every edit is diffed against a **base snapshot** of the record it was derived from. At
push time the engine compares that snapshot against what the server currently holds:

- Server matches the snapshot → the edit applies cleanly.
- Server has moved on → a `ConflictRecord` is raised and surfaced in the UI, resolved with
  **Keep Mine**, **Keep Server**, or a field-by-field **Merge**.

## Sync window

Sync keeps a rolling 30-day window. **Load older activity** at the foot of the timeline pages
further back on demand — down to the child's birth — without dropping anything already cached.

## Widgets and the App Group

The widget extension reads the same SwiftData store as the app through a shared **App Group**
container (`Sources/Persistence/LocalStore.swift`). Widget write actions — starting or stopping a
timer, Quick Log — go through the local cache and push to the server immediately, falling back to
the sync queue when offline, exactly like in-app writes.

Live Activities are the one exception. Widget and Siri intents run in the extension process,
where ActivityKit cannot be driven, so the app reconciles the Live Activity banner whenever it
next becomes active.
