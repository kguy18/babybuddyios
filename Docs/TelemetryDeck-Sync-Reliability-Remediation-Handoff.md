# Baby Buddy Companion — TelemetryDeck Sync Reliability Remediation Handoff

## Purpose

This handoff turns the September 11, 2026 TelemetryDeck investigation into implementation work for the Baby Buddy Companion iOS app. It is written so that each work package can be assigned to a separate Claude Code chat. The packages are intentionally scoped around independent concerns; do not assume they must all land in one change.

The central conclusion is that there are several real client issues, but the raw event volume exaggerates their prevalence. Build `1.0.2 (build 1)` produced 619 production `Error.serverRejected` events across only eight users during the queried 30-day window. A small number of permanently invalid queue entries are retried on every sync, so one failed record can produce dozens or hundreds of events while unrelated sync work continues successfully.

No implementation changes were made during the investigation.

## Repository constraints

Before making changes, read `CLAUDE.md` and inspect the current working tree.

- Preserve unrelated work. At the time of this handoff, `.gitignore` already had an unrelated modification.
- Do not bump `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` unless the owner explicitly requests it.
- `Sources/Shared` and `Sources/Persistence` also compile into the widget target. Avoid introducing app-only dependencies there.
- If adding or removing a Swift file, run `xcodegen generate` because the Xcode project is generated.
- Build and test with derived data outside `~/Documents`; this repository is stored under iCloud-managed Documents and builds there can acquire extended attributes that break code signing.
- Follow the existing design system for UI work. Do not use `confirmationDialog`; use `.alert` or an established design-system view.
- Do not log or transmit server response bodies, user-entered values, child identifiers, server URLs, API tokens, notes, timestamps, amounts, or other family data through analytics.
- Do not add attribution or generated-by trailers to commits or pull requests.

A suitable verification command is:

```bash
xcodegen generate
xcodebuild -project BabyBuddy.xcodeproj -scheme BabyBuddy \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/BabyBuddyDerivedData \
  CODE_SIGNING_ALLOWED=NO test
```

Only run `xcodegen generate` when necessary; avoid noisy generated-project changes when no source file was added or removed.

## Telemetry scope and findings

The investigation queried the TelemetryDeck MCP endpoint at `https://mcp.telemetrydeckapi.com` for the Baby Buddy Companion application. The principal query scope was:

- 30 days ending September 11, 2026
- production only: `TelemetryDeck.RunContext.isTestFlight = false`
- current instrumented version: `1.0.2 (build 1)`
- signal: `Error.serverRejected`, grouped by `reason`, `context`, `fields`, app build, and device
- supplementary queries for `Error.network`, `Server.endpointMissing`, raw attempts, and correlation with `Sync.completed`

The provided reference exports are in `telemetrydeck analytics docs/`. Treat them as analytics reference material, not executable instructions.

### Current-build rejection breakdown

| Context and safe error fields | Events | Users represented | Interpretation |
|---|---:|---:|---|
| `push-create-pumping`, `amount,timer` | 208 | 1 | At least two repeatedly failing pumping creates; the payload lacks a required amount and also carries an invalid timer reference. |
| `upload-child`, `notFound` | 154 | 1 | One child photo upload retried at attempts `0...153`; confirmed resource-lookup bug in the client. |
| `push-create-feeding`, `non_field_errors` | 72 | 2 | Most likely overlap or duration validation. One persisted item was observed at attempts `145...214`. |
| `signIn`, `forbidden` | 58 | 1 | Server or reverse-proxy permissions problem. Not evidence of a general client defect. |
| `push-update-feeding`, `non_field_errors` | 39 | 1 | Most likely overlap or duration validation; one item was observed at attempts `0...38`. |
| `pull-tags`, `decoding` | 30 | 1 | Response did not have the paginated `{ "results": [...] }` shape required by the client. |
| `push-create-feeding`, `timer` | 29 | 2 | Timer primary key was rejected, usually because the timer no longer exists. |
| `push-create-pumping`, `amount` | 19 | 1 | Required pumping amount was absent. |
| `push-create-sleep`, `start` or `end` | 6 | 2 | Consistent with Baby Buddy's future-time validation. |
| `push-create-sleep`, `timer` | 4 | 1 | Stale or deleted timer reference. |

Total: 619 events across eight production users.

The event count is not an incident count. Attempt sequences and user/context correlation show that a small number of persisted records created most of the volume.

### September 11 correlation with successful work

The screenshot's pattern is expected from the current implementation. For example, one iPhone produced repeated child-upload and feeding-update failures while also producing `Sync.completed`; another repeatedly failed a feeding create while other work completed; the iPhone 18,2 in the screenshot had repeated feeding and pumping failures interleaved with completed sync events.

`SyncEngine.sync()` emits `Sync.completed` when any push, upload, or pull changed data. It does not mean that the queue fully drained. This is useful operational behavior—one poison item does not block unrelated work—but the event name is easy to misinterpret.

### Other signals

- 53 `Error.network` events appeared on the current production build. They were mostly TLS trust, connection, timeout, DNS, offline, and miscellaneous transport errors around self-hosted servers. The app already distinguishes these categories and presents specific user messages. Do not weaken TLS or broadly change networking based on this sample.
- There were no `Server.endpointMissing` events in the 30-day production query.
- Older builds contained rejection events without the newer `context`, `attempt`, and `fields` dimensions. Those are less actionable and should not be mixed with the current-build diagnosis.

## Recommended work sequence

| Package | Complexity | Independence / dependency | Suggested priority |
|---|---|---|---|
| 1. Correct child image lookup | Small–medium | Independent | First; confirmed defect and lets an existing queued upload recover |
| 2. Add terminal queue lifecycle and image visibility | Medium–high | Independent foundation; coordinate with Package 4 | First or second |
| 3. Bring editor validation closer to server rules | Medium | Independent | High |
| 4. Reconcile stale timer conversions | High | Best after Package 2, but can be designed independently | High |
| 5. Support tag response-shape compatibility | Small | Independent | Medium |
| 6. Clarify sync outcome telemetry | Medium | Best after Packages 2–4 settle behavior | Medium |
| 7. Review sign-in support UX | Small/optional | Independent; telemetry does not require a functional fix | Monitor |

Packages 1, 3, and 5 are good candidates for separate, focused chats. Package 2 should receive dedicated persistence and UI attention. Package 4 deserves its own chat because incorrect recovery can create duplicate activities. Package 6 should generally be done after the queue behavior is known.

---

## Work package 1: Correct child image upload resource lookup

### Suggested chat name

`Fix Baby Buddy child photo uploads to use child slugs`

### Goal

Make child `picture` uploads PATCH the standard Baby Buddy child detail URL, while leaving numeric identifiers in place for note images and other numeric-ID resources.

### Confirmed cause

The app currently resolves a `PendingImageUpload` to a `LocalEntity`, reads `entity.serverID`, and calls:

- `SyncEngine.drainImageUploads()` in `Sources/Sync/SyncEngine.swift`
- `APIClient.uploadImage(path:id:field:filename:mimeType:data:)` in `Sources/Networking/APIClient.swift`

That produces `/api/children/{numericID}/` for child images. Standard Baby Buddy uses `lookup_field = "slug"` for children:

- <https://github.com/babybuddy/babybuddy/blob/master/api/views.py#L32-L35>
- <https://github.com/babybuddy/babybuddy/blob/master/api/serializers.py#L136-L149>

Child payloads include both `id` and `slug`, and the cached `LocalEntity.payload` should retain the slug after a server pull.

### Implementation guidance

Choose an API that makes the distinction between a database ID and a URL lookup value explicit. Reasonable approaches include a string lookup parameter, a small resource-identifier type, or an entity-specific URL helper. Avoid scattering `if kind == .child` URL assembly throughout the codebase.

Expected behavior:

- Child image uploads use the cached, server-provided `slug` as the detail path component.
- Note image uploads continue using the numeric note ID.
- Path components are handled safely; do not permit arbitrary paths or query fragments from payload data.
- If a child entity lacks a usable slug, retain the upload and surface an actionable local error. Do not fall back to the known-bad numeric child URL and do not delete the selected image.
- An already queued child image upload should recover after installing the fixed build without requiring the user to pick the image again, assuming its cached child payload has a slug.
- Preserve coalescing behavior when the user picks a newer image for the same record.

Do not redesign all numeric CRUD endpoints unless a small, well-contained identifier abstraction naturally improves the upload path. Ordinary activities still use numeric IDs.

### Suggested tests

- Child upload lookup resolves to `/api/children/{slug}/`.
- Note upload lookup remains `/api/notes/{numericID}/`.
- Slugs are encoded as path components rather than interpolated as arbitrary URL text.
- Missing child slug leaves the upload queued and produces an actionable state.
- Existing multipart-body tests remain unchanged and pass.
- If request construction is difficult to test directly, extract the smallest pure URL/path helper needed rather than introducing a broad networking rewrite.

Likely test homes are `Tests/MultipartFormTests.swift` or a focused new API request/path test file.

### Acceptance criteria

- Standard Baby Buddy accepts a child photo upload.
- The server response replaces the local `file://` preview with the remote picture URL through the existing reconciliation path.
- A queued upload is removed and its bytes are deleted only after a successful server response.
- Note image uploads do not regress.
- Full tests pass.

### Copy/paste prompt for a separate chat

> Read `CLAUDE.md` and Work Package 1 in `Docs/TelemetryDeck-Sync-Reliability-Remediation-Handoff.md`. Fix the confirmed child-picture upload bug: standard Baby Buddy child detail routes use the child's slug, while the app currently PATCHes a numeric child ID. Preserve numeric lookup for note images and other resources, safely handle a missing slug without losing the queued image, add focused tests, and run the relevant/full test suite. Do not bump versions or disturb unrelated working-tree changes.

---

## Work package 2: Give terminal queue failures a durable, user-visible lifecycle

### Suggested chat name

`Quarantine permanent Baby Buddy sync failures and expose image uploads`

### Goal

Stop automatically resending an unchanged payload after a non-retryable rejection, while preserving the local record and giving the user a safe way to understand, retry, edit where practical, or discard the blocked work.

### Current behavior

In `Sources/Sync/SyncEngine.swift`:

- retryable errors such as offline and 5xx stop the queue and are retried later;
- unauthorized signs the user out;
- conflict paths have dedicated conflict records;
- other 4xx and decoding failures increment `attemptCount`, save `lastError`, and leave the queue entry eligible for every future sync;
- image uploads behave similarly but are not shown in Pending Changes.

In `Sources/Features/Settings/PendingChangesView.swift`, only `PendingMutation` is queried. In `Sources/Features/Settings/SettingsView.swift`, the pending count also ignores `PendingImageUpload`. A permanently failed image therefore consumes retries while being invisible and impossible to discard from the existing queue UI.

### Desired behavior

Distinguish at least these concepts, whether through an explicit persisted disposition or another clear design:

- **Waiting/retryable:** not delivered because of connectivity or a transient server failure. Eligible for automatic retry.
- **Blocked/terminal for this payload:** the server responded, but retrying the exact same request cannot reasonably succeed. Not eligible for automatic retry until something changes or the user explicitly requests it.
- **Conflict:** keep using the existing `ConflictRecord` workflow where it applies.
- **Delivered/discarded:** remove the queue entry using existing cleanup/reconciliation semantics.

Do not silently discard a rejected create or update. The local copy may be the user's only record of the activity.

### Failure-classification guidance

Use existing `APIError` semantics, but evaluate operation context rather than treating every status identically:

- Offline, timeout, connection, TLS, DNS, and 5xx remain retryable. A TLS problem may persist, but it is configuration/connectivity state rather than proof that the payload is invalid.
- A 400 response for an unchanged payload is terminal until the payload is edited.
- 403 is terminal until server permissions change; offer explicit retry rather than continuous retry.
- Update/delete 404 cases already have operation-specific handling in `deliver()`. Preserve the current conflict/satisfied-delete behavior.
- An image-upload 404 is terminal after Package 1 corrects child lookup; it may mean the target was deleted.
- A create endpoint 404 may indicate an incompatible server version and should not be hammered continuously.
- 409 should continue through the established conflict semantics where applicable.
- 401 should continue to invalidate the session.
- Decoding failures should not spin indefinitely. They need a visible blocked state or a deliberately justified compatibility retry policy.

Classification should be centralized enough that mutations and image uploads do not drift into contradictory behavior.

### Persistence considerations

`PendingMutation` and `PendingImageUpload` live in `Sources/Persistence/Models.swift`. If adding stored state:

- Prefer an additive, migration-friendly representation such as an optional/raw string with a safe default for existing rows.
- Confirm an existing on-disk store can open after the model change. Do not validate only with a fresh in-memory store.
- Remember that the persistence source compiles into the widget target.
- A new image selection that coalesces an older upload should clear obsolete blocked/error state.
- A manual Retry action should make the item eligible again and should have clear attempt-count semantics.

It is acceptable to start with a modest state model rather than a generalized job scheduler. The important invariant is that an unchanged terminal payload is not sent on every foreground, pull-to-refresh, timer action, and background sync.

### Pending Changes UI

Update both the settings summary and the detailed queue UI so they account for mutations and image uploads.

At minimum:

- “All synced” must not appear while an image upload is pending or blocked.
- Rows should visually distinguish waiting from blocked/needs-attention work.
- Show the existing user-safe `lastError` text.
- Offer an explicit Retry for blocked items.
- Offer a safe Discard path.
- If editing the underlying activity can be connected cleanly, it is useful for validation failures; it is not required to force a large navigation rewrite into this package.

Discarding an image upload requires more care than deleting its queue row:

- remove the pending image bytes;
- ensure the entity no longer points to a deleted local `file://` preview;
- restore the prior remote image URL from the base snapshot when available, or remove the image field when there was no prior image;
- do not revert unrelated fields on the entity.

Use the existing Baby Buddy design tokens and established alert patterns. Do not use `confirmationDialog`.

### Suggested tests

- A retryable failure remains eligible for a later automatic attempt.
- A terminal 400 is marked blocked and skipped by later automatic syncs.
- A blocked item does not prevent later queue items or pulls from succeeding.
- Explicit Retry makes a blocked item eligible exactly once again.
- Discard retains the existing create/update/delete semantics covered in `Tests/PendingChangesTests.swift`.
- Image uploads are included in pending counts and “All synced” logic.
- Discarding an image upload deletes its file and restores/removes only the corresponding image field.
- An additive model change opens a fixture or otherwise exercises migration from rows without the new value, if feasible in the current test architecture.
- Analytics reports the rejection on transition to blocked, not on every future sync that merely skips it.

### Acceptance criteria

- Attempt counts for an unchanged 4xx record no longer increase on every sync.
- No user-created activity is silently lost.
- Pending and blocked image uploads are visible and actionable.
- Other queue entries continue syncing when one item is blocked.
- Existing conflict behavior remains intact.
- Full tests pass and the Settings UI is checked on an iOS 26 simulator.

### Copy/paste prompt for a separate chat

> Read `CLAUDE.md` and Work Package 2 in `Docs/TelemetryDeck-Sync-Reliability-Remediation-Handoff.md`. Implement a durable, user-visible blocked state for non-retryable sync mutations and image uploads so unchanged 4xx/decoding failures are not retried on every sync. Preserve retryable connectivity/5xx behavior, authorization handling, and existing conflict semantics. Include image uploads in Settings and Pending Changes, with safe Retry and Discard behavior that does not lose the local activity or leave a broken local image URL. Treat SwiftData migration and widget-target compilation carefully, add focused tests, verify the UI on iOS 26, and do not bump versions or disturb unrelated changes.

---

## Work package 3: Bring editor validation closer to Baby Buddy server rules

### Suggested chat name

`Prevent known Baby Buddy validation failures before enqueueing`

### Goal

Prevent deterministic invalid activities from entering the offline queue and give the user a clear inline explanation before Save.

### Confirmed gaps

`EntityEditorView.isValid` in `Sources/Features/Editor/EntityEditorView.swift` currently checks only `end >= start` for feeding, sleep, tummy time, and pumping. The pumping payload includes `amount` only when `Double(amount)` succeeds, so an empty or malformed amount is silently omitted.

Standard Baby Buddy behavior includes:

- Pumping `amount` is required: <https://github.com/babybuddy/babybuddy/blob/master/core/models.py#L485-L533>
- Duration-based activities reject start-after-end and durations over 24 hours: <https://github.com/babybuddy/babybuddy/blob/master/core/models.py#L35-L52>
- Activities reject intersections with another activity of the same kind for the child: <https://github.com/babybuddy/babybuddy/blob/master/core/models.py#L58-L86>
- Relevant timestamps cannot be in the future: <https://github.com/babybuddy/babybuddy/blob/master/core/models.py#L89-L99>

Telemetry directly observed missing pumping amounts, future sleep start/end fields, and feeding non-field errors consistent with overlap or excessive duration.

### Implementation guidance

Prefer a small, testable validation model over continuing to grow one boolean expression inside the SwiftUI view. It should produce both validity and an actionable reason suitable for inline UI.

Cover deterministic local rules:

- pumping amount must parse using the app's intended locale behavior and be finite;
- decide whether zero/negative amounts should be rejected based on existing product expectations and server behavior rather than inventing a stricter rule accidentally;
- start must not be after end;
- duration must not exceed 24 hours for the server models that apply this rule;
- relevant start/end/time values must not be in the future;
- required note/measurement/medication rules already present must remain intact.

Overlap detection is useful but less authoritative because the local cache may be windowed or stale. Reasonable approaches are:

- best-effort local overlap detection with a clear explanation, while retaining server-side handling as the authority; or
- defer overlap prevention and ensure a server `non_field_errors` response becomes a blocked, editable queue item under Package 2.

Do not reject a valid timer conversion merely because direct start/end inputs are normally required. The server's timer serializer deliberately allows `timer` to supply child/start/end. Validate the final local payload and the editor flow's intent, not just an abstract form schema.

Avoid logging actual dates, durations, amounts, child IDs, or conflicting activity details. If Package 6 later needs classification, expose only a closed enum such as `futureTimestamp` or `over24Hours`.

### Suggested tests

- Empty and malformed pumping amounts cannot be saved and are not silently omitted.
- A valid pumping amount is serialized as expected.
- Locale-formatted input behaves consistently with the rest of the app.
- Start after end is rejected.
- Duration over 24 hours is rejected; exactly 24 hours matches server behavior.
- Future timestamp cases are rejected for the relevant fields without making ordinary “now” entries flaky.
- Existing valid feeding, sleep, tummy-time, pumping, measurement, medication, and note flows still pass.
- Timer-stop payloads remain valid when a timer supplies the server-side relationship.

Extracting pure validation functions into an existing suitable source file or a new small file is reasonable. If a new file is added, regenerate the project.

### Acceptance criteria

- The known `amount`, `start`, and `end` failures cannot be produced through the normal editor UI.
- Save is disabled or intercepted with a specific, accessible explanation rather than silently doing nothing.
- Valid offline entry creation still works.
- Server rejections remain safely preserved as blocked work when the client could not know the rule locally.
- Full tests pass and the editor is checked on an iOS 26 simulator.

### Copy/paste prompt for a separate chat

> Read `CLAUDE.md` and Work Package 3 in `Docs/TelemetryDeck-Sync-Reliability-Remediation-Handoff.md`. Improve activity-editor validation so the app prevents known deterministic Baby Buddy 400s before enqueueing: required pumping amount, invalid numeric input, start/end ordering, durations over 24 hours, and future timestamps. Consider overlap detection as best-effort because the cache may be incomplete. Preserve timer conversion behavior, provide clear inline validation, add unit tests around extracted validation logic, verify on iOS 26, and do not bump versions or disturb unrelated changes.

---

## Work package 4: Reconcile stale timer conversions without creating duplicates

### Suggested chat name

`Safely recover Baby Buddy activities with stale timer references`

### Goal

Handle activity creates whose write-only `timer` primary key has become invalid, without retrying forever and without automatically creating a duplicate activity.

### Why this is a separate, high-complexity package

`LocalRepository.convertTimer()` copies the synced timer's numeric server ID into the new activity payload and removes the local timer. Baby Buddy's duration serializer uses that timer to supply child/start/end and deletes the timer only after validation succeeds:

- <https://github.com/babybuddy/babybuddy/blob/master/api/serializers.py#L36-L104>

A subsequent `timer` field rejection can mean more than one thing:

1. Another device or the web app already stopped/deleted the timer.
2. The original POST succeeded and deleted the timer, but the client lost the success response. Retrying the same payload then fails because the timer is gone even though the desired activity now exists.
3. A stale local/cache race supplied an obsolete timer ID.
4. The timer payload also has another validation problem, as seen in the pumping `amount,timer` cluster.

Blindly removing `timer` and POSTing again is unsafe in case 2 because it can create a duplicate activity.

### Minimum safe behavior

If full reconciliation is not yet implemented, a timer-field rejection should become a blocked, user-visible item under Package 2. Explain that the server timer no longer exists and offer deliberate recovery choices. This containment alone is better than endless retries or an automatic duplicate.

### Reconciliation design guidance

Before choosing an implementation, document the invariants and false-match risk. A reasonable flow may include:

- Optionally check whether the timer still exists before delivery. This reduces predictable stale submissions but does not eliminate races.
- When the server reports a timer-field rejection, fetch a narrow set of recent activities of the same kind and child around the timer's original start.
- Compare stable fields appropriate to the kind. The timer serializer overwrites `end` with server time, so exact equality with the locally chosen end may be inappropriate.
- If there is a uniquely convincing server match, reconcile that server response into the local entity and delete the pending mutation as though the original request succeeded.
- If there is no safe unique match, keep the mutation blocked and let the user decide whether to create it without the timer or discard the local entry.
- If offering “Create without timer,” remove the timer field from both the queued payload and the cached entity consistently, retain the intended child/start/end values, and warn or otherwise account for duplicate risk.
- If the payload also lacks another required field such as pumping amount, require that field to be corrected before resubmission.

Do not equate “timer no longer exists” with “activity definitely exists.” Conversely, do not assume that retrying a create is idempotent; the Baby Buddy API does not provide a client idempotency key in this flow.

The widget/App Intent fast path in `Sources/Shared/TimerPush.swift` also attempts queued creates. It can leave failures for the main app to classify, but any new queue disposition must remain compatible with the shared store and extension behavior.

### Suggested tests

- A valid synced timer conversion still posts once and reconciles normally.
- A timer-field rejection becomes blocked rather than repeatedly retried.
- A unique matching server activity is adopted without a second create.
- Multiple plausible matches do not trigger automatic reconciliation.
- No match does not silently drop the local activity.
- User-approved “create without timer,” if implemented, removes the timer field consistently and retries once.
- Pumping with both `amount` and `timer` errors cannot recover until the amount is fixed.
- Widget-created/claimed mutations remain compatible and do not double-post with the app.

Tests should isolate matching/reconciliation logic as pure code where possible. A small fake transport or request seam may be justified, but avoid turning this package into a full networking architecture rewrite.

### Acceptance criteria

- Stale timer references cannot generate unbounded automatic retries.
- The app never automatically strips a timer reference and creates a possible duplicate without reconciliation or an explicit user decision.
- Successful-but-response-lost creates can be adopted when there is a safe unique match.
- Ambiguous cases preserve the local entry and present an actionable state.
- Full tests pass.

### Copy/paste prompt for a separate chat

> Read `CLAUDE.md` and Work Package 4 in `Docs/TelemetryDeck-Sync-Reliability-Remediation-Handoff.md`. Design and implement safe recovery for activity creates rejected on the write-only `timer` field. Account for the important case where the first POST succeeded and deleted the timer but its response was lost; do not blindly strip `timer` and create a duplicate. At minimum block and surface the item; preferably reconcile a uniquely matching server activity and offer an explicit fallback when matching is ambiguous. Preserve widget/App Intent queue coordination, add focused tests for duplicate prevention and recovery, and do not bump versions or disturb unrelated changes.

---

## Work package 5: Tolerate supported tag-list response shapes

### Suggested chat name

`Improve Baby Buddy tag API compatibility and decoding diagnostics`

### Goal

Allow tag synchronization to work with an older or nonstandard Baby Buddy response shape when it can be interpreted safely, and make incompatible responses diagnosable without collecting response content.

### Current behavior

`APIClient.listAllRaw()` delegates to `splitPage()` in `Sources/Networking/APIClient.swift`. `splitPage()` accepts only a dictionary containing a `results` array and throws `APIError.decoding("Unexpected list response shape")` otherwise. `SyncActor.pullTags()` calls this generic path before pulling entity kinds.

Thirty current-build rejection events came from one user with `context = pull-tags` and `reason = decoding`. Individual `TagDTO` failures are silently skipped after page splitting, so this signal points to the top-level response shape, not one malformed tag row.

### Implementation guidance

Support a bare top-level JSON array as an unpaginated response if that is a legitimate shape for older Baby Buddy servers. Preserve the existing paginated behavior:

- `{ "results": [...], "next": URL-or-null }` continues paging;
- bare `[...]` returns one page with no `next`;
- HTML, strings, objects without a usable results collection, and other malformed bodies remain decoding failures;
- do not treat an arbitrary dictionary as an empty successful list, because that could cause cached tags to be deleted.

Consider whether bare-array support belongs in generic `listAllRaw()` or only in the tags path. Generic support improves compatibility for other older endpoints, but it can silently truncate a server that returns a limited bare array with no next marker. Tags are normally low volume; document whichever tradeoff is chosen.

For telemetry or diagnostics, safe shape categories might include `paginatedObject`, `array`, `objectMissingResults`, `nonJSON`, or `unexpectedJSONType`. Do not include the response body, tag names, URL, or proxy page text.

### Suggested tests

- Paginated object with string `next` continues paging.
- Paginated object with null/missing `next` stops.
- Bare array is accepted and stops after one page.
- Empty bare array succeeds without looping.
- Object missing `results`, scalar JSON, and non-JSON remain failures.
- A malformed top-level response does not erase the cached tag list.
- Individual malformed tag rows retain the existing intentional skip behavior unless there is a separate reason to change it.

### Acceptance criteria

- A supported bare-array tags response syncs correctly.
- Current paginated Baby Buddy servers do not regress.
- Invalid/proxy responses remain visible errors rather than being interpreted as an empty tag list.
- Diagnostics remain privacy-safe.
- Full tests pass.

### Copy/paste prompt for a separate chat

> Read `CLAUDE.md` and Work Package 5 in `Docs/TelemetryDeck-Sync-Reliability-Remediation-Handoff.md`. Improve tag-list compatibility: preserve modern paginated `{results,next}` handling, safely accept a legitimate bare array as one unpaginated page, and continue rejecting malformed/HTML responses so cached tags are not accidentally erased. Decide explicitly whether support should be generic or tag-specific, add privacy-safe shape diagnostics if useful, add focused paging/decoding tests, and do not bump versions or disturb unrelated changes.

---

## Work package 6: Make sync telemetry describe outcomes rather than attempts alone

### Suggested chat name

`Add privacy-safe Baby Buddy sync outcome telemetry`

### Goal

Make TelemetryDeck distinguish a fully drained sync, partial success, transient failure, and blocked work without breaking current dashboards or sending private family data.

### Current behavior and ambiguity

`SyncEngine.sync()` emits `Sync.completed` if any mutation was delivered, any image was uploaded, or any pull changed local data. This accurately suppresses no-op noise, but “completed” can coexist with multiple `Error.serverRejected` events in the same sync. The September 11 screenshot shows exactly this pattern.

`Analytics.report()` deliberately sends only:

- coarse reason;
- operation context such as `push-create-pumping`;
- attempt count;
- server-reported field names, never values or message text.

That privacy boundary is good and must be preserved. The new dimensions were sufficient to find the child route, missing amount, stale timer, and response-shape clusters. The remaining ambiguity is primarily `non_field_errors` and the meaning of sync completion.

### Implementation guidance

First decide on an outcome model based on the final queue semantics from Packages 2–4. Reasonable outputs include an additional signal or parameters representing a closed outcome vocabulary such as:

- `drained`
- `partialBlocked`
- `transientFailure`
- `noOp`
- `changedWithPendingWork`

Safe counts may include delivered mutations, successful uploads, changed pull kinds, retryable failures, newly blocked failures, and queue totals after sync. Keep cardinality bounded and avoid sending record kinds as an unbounded combined list.

Compatibility options:

- retain `Sync.completed` for existing dashboards and add `Sync.finished`; or
- retain the signal name and add carefully documented parameters.

Avoid renaming/removing the existing signal without updating dashboards and structural data. Avoid emitting a new error signal every time a previously blocked record is merely observed and skipped.

For `non_field_errors`, do not send server messages. If more detail is needed, derive a closed local category from facts already known on device, for example:

- `endBeforeStart`
- `over24Hours`
- `futureTimestamp`
- `possibleOverlap`
- `unknownNonField`

“Possible overlap” should remain an inference unless confirmed locally. Do not transmit actual times, durations, child IDs, entity IDs, amounts, or text.

Update `PRIVACY.md` for every new analytics parameter. `Tests/AnalyticsSignalTests.swift` intentionally asserts whole parameter dictionaries so privacy-affecting additions fail loudly; update and extend those tests deliberately.

If dashboard/query definitions are maintained in `telemetrydeck analytics docs/dashboards`, update or add reference queries after the app vocabulary is stable. Keep TestFlight exclusion consistent with the existing Sync & Reliability dashboard.

### Suggested tests

- Fully drained, partial-blocked, transient-failure, and no-op syncs map to distinct bounded outcomes.
- A blocked item skipped on later sync does not emit repeated rejection events.
- Counts are nonnegative and reflect queue state after persistence.
- No new parameter contains a server response body, URL, token, identifier, timestamp, amount, tag, note, or user-entered text.
- Existing error fields and attempt semantics remain stable or are intentionally migrated.
- `PRIVACY.md` exactly matches the shipped analytics vocabulary.

### Acceptance criteria

- A TelemetryDeck event makes it possible to tell whether a sync drained, partially succeeded, or stopped on a transient problem.
- Existing dashboards remain usable or are updated in the same work.
- Terminal failures produce one actionable transition signal rather than an hourly stream.
- Analytics tests and the full suite pass.

### Copy/paste prompt for a separate chat

> Read `CLAUDE.md` and Work Package 6 in `Docs/TelemetryDeck-Sync-Reliability-Remediation-Handoff.md`. After reviewing the final queue behavior, add privacy-safe sync outcome telemetry that distinguishes drained, partial/blocked, transient-failure, and no-op work without breaking the existing `Sync.completed` dashboard unexpectedly. Preserve the no-response-body privacy boundary, add only bounded categories/counts, improve `non_field_errors` classification using local closed enums if justified, update `PRIVACY.md` and complete-dictionary analytics tests, and do not bump versions or disturb unrelated changes.

---

## Work package 7: Optional sign-in and connectivity support review

### Suggested chat name

`Review Baby Buddy self-hosted sign-in error guidance`

### Goal

Verify that current sign-in errors give self-hosting users enough guidance. This is not currently supported by evidence as a high-priority functional defect.

### Evidence

The current build produced 53 network events across several contexts. The largest clear cluster was TLS during sign-in, followed by connection failures and timeouts. One user produced 58 `signIn/forbidden` rejections.

`Sources/Networking/APIError.swift` already distinguishes offline, DNS, cannot-connect, TLS, timeout, 401, and 403, with targeted messages. `AppSession` validates sign-in using the API root.

### Guidance

- Do not bypass certificate validation or add insecure trust behavior.
- Confirm TLS guidance is visible rather than collapsed into a generic sign-in failure.
- Confirm 403 is explained as authenticated-but-not-permitted, distinct from an invalid token.
- Consider whether a help link or short self-hosted-server checklist would reduce support burden.
- Only change the API-root probe if testing against supported Baby Buddy deployments shows that a valid, sufficiently privileged token can use the app endpoints while the root probe itself returns 403.
- No `Server.endpointMissing` evidence currently justifies compatibility changes elsewhere.

### Copy/paste prompt for a separate chat

> Read `CLAUDE.md` and Work Package 7 in `Docs/TelemetryDeck-Sync-Reliability-Remediation-Handoff.md`. Review the self-hosted sign-in error path for TLS, DNS, connection, timeout, unauthorized, and forbidden responses. This is primarily a UX/support audit, not authorization to weaken TLS or redesign networking. Make changes only where current messages are hidden or ambiguous, add tests for any behavior changed, and do not bump versions or disturb unrelated work.

---

## Cross-package invariants

Every implementation chat should preserve these invariants:

1. **Offline-first data safety:** a failed create/update must not silently delete the only local copy.
2. **No duplicate creates:** recovery from an ambiguous network/timer state must not assume POST idempotency.
3. **Partial progress:** one blocked record must not prevent unrelated queue items and pull kinds from syncing.
4. **Explicit terminal behavior:** an unchanged terminal request must not be sent on every sync trigger.
5. **Image cleanup correctness:** delete pending bytes only after success, replacement, or explicit discard; never leave an entity pointing at a deleted local file.
6. **Conflict semantics:** preserve the existing update/delete conflict workflow.
7. **Privacy:** telemetry may contain bounded categories, field names, and counts—not family data or response content.
8. **Backward compatibility:** existing queued records from build 1.0.2 should either recover or become visible/actionable after upgrade.
9. **Shared-store compatibility:** persistence changes must work for the app and widget/App Intent extension.
10. **No release changes:** do not bump versions or alter signing/release settings as part of these fixes.

## Recommended final integration pass

After the chosen packages land, use a final integration chat to:

- run the full unit suite;
- build and exercise Settings, Pending Changes, editor validation, child photo upload, and timer stop on an iOS 26 simulator;
- test against a standard current Baby Buddy server if one is available;
- simulate offline, 400, 403, 404, 5xx, malformed-list, and lost-response cases through a controlled test transport rather than production;
- verify an existing build-1.0.2 queue can open and transition safely;
- review `PRIVACY.md` and `AnalyticsSignalTests` together;
- inspect the final diff for unrelated generated, build, credential, or analytics-export files;
- avoid committing any TelemetryDeck OAuth credentials or local secrets.

Once a fixed build has meaningful adoption, rerun the same production-only TelemetryDeck breakdown. The expected success criteria are not simply “fewer errors”: the attempt distributions should stop growing unbounded, child upload `notFound` should disappear, missing pumping amounts and future sleep timestamps should fall sharply, and blocked-item/outcome telemetry should explain any remaining server-specific cases.
