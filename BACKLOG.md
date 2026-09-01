# Backlog

Build-ready prompts for features graduated from the 2026-09-01 feature slate. Each entry
links its GitHub issue; work one entry per branch and PR. Every candidate was verified
against the source (not already implemented) and the upstream Baby Buddy API before
graduating.

**Conventions for every entry** (assume these; the prompts don't repeat them):
- Style new UI with the design-system tokens (`BBColor`/`BBFont`/`BBRadius` in
  `Sources/Shared/DesignSystem.swift`, components in
  `Sources/Features/Shared/DesignComponents.swift`); light + dark.
- All writes go through `LocalRepository` and the existing offline sync queue.
- New user-facing behavior gets a Settings control instead of a hardcoded default.
- Add or extend unit tests for any non-trivial logic; run the full test suite.
- The project is XcodeGen: run `xcodegen generate` after adding/removing files, and build
  with `-derivedDataPath /tmp/bb-build` (codesign fails inside the iCloud-managed tree).

---

## 1. Adjustable timer start time — [#72](https://github.com/kguy18/babybuddyios/issues/72)

> In the BabyBuddy iOS app, make timer start times adjustable. `StartTimerSheet.swift`
> hard-codes `"start": now` (~line 116): add a "Starts" row with quick offset chips
> (Now / −5 / −15 / −30 min) and a compact `DatePicker`, so a timer can be back-dated at
> start. In `StopTimerSheet.swift`, let the start be corrected before logging the record.
> Also surface a Restart action on the running-timer card that calls
> `PATCH /api/timers/{id}/restart/` (add it to `APIClient`; `start` is a writable
> date-time on POST/PATCH). Converted records must inherit the corrected start via the
> existing conversion flow. Extend `StartTimerTests`/`TimerConvertTests`.

## 2. Medication next-dose reminders — [#73](https://github.com/kguy18/babybuddyios/issues/73)

> Add next-dose tracking to medications. The `next_dose_interval` duration field already
> exists in `DTOs.swift:212` but the medication editor (`EntityEditorView`,
> `medicationDetails`) drops it: add an optional interval input (e.g. 4h/6h/8h/12h/24h
> picker plus custom), send/parse it through the payload, and show a "next dose OK at
> h:mm" countdown on medication rows and the Dashboard when the interval hasn't elapsed.
> Then add the app's first `UserNotifications` integration: schedule a local notification
> at `time + next_dose_interval` on save, cancel/reschedule on edit and delete, and
> reconcile after each sync pull (web-logged doses). Opt-in via a Settings toggle that
> requests permission on first enable. Tests for interval parsing and schedule/cancel
> logic behind a protocol-mocked notification center.

## 5. Next-feed estimate — [#74](https://github.com/kguy18/babybuddyios/issues/74)

> Add a next-feed estimate. In `ChildStatus.swift` (or a sibling pure helper), compute
> the median interval of the last ~10 feed-to-feed gaps for the selected child from the
> cached feedings; expose "usually eats every ~Xh Ym — next around h:mm". Hide the
> estimate when there are fewer than ~5 recent feedings or the intervals are wildly
> irregular (e.g. median absolute deviation above a sane bound). Surface it as a quiet
> line on the Dashboard and a field in `StatusWidget`. Settings toggle to disable.
> Pure-function unit tests for the median/irregularity logic.

## 6. 24-hour rhythm chart — [#75](https://github.com/kguy18/babybuddyios/issues/75)

> Add a rhythm chart card to the Trends tab (`InsightsView`). Plot the selected window
> (existing 7/14/30-day `ChartPeriod`) as horizontal day-rows on a 24-hour x-axis: sleep
> records as bars (split spans that cross midnight across the two day rows), feedings as
> dots at their start time. Colors: `BBColor.sleep` and `BBColor.feeding`. Aggregation
> lives in `ChartAggregation.swift` as pure, calendar-injectable functions with unit
> tests (midnight-spanning sleep is the key case). Per-row accessibility labels; empty
> state consistent with the existing cards.

## 7. Handoff summary share — [#76](https://github.com/kguy18/babybuddyios/issues/76)

> Add a "Share today" action (Dashboard toolbar or context menu) that composes a
> plain-text summary of the selected child's day from the local cache — last feeding
> with amount/type, sleep count and total, last diaper, medications with doses and
> times, plus today's tallies — and hands it to the iOS share sheet via `ShareLink`.
> Reuse the day-tally logic behind the Timeline day headers rather than duplicating it.
> Works fully offline. Unit-test the formatter (given seeded records, exact expected
> string), including the empty-day case.

## 11. Undo toast after every log — [#77](https://github.com/kguy18/babybuddyios/issues/77)

> Add an undo toast. After any record create (editor save, timer stop/log, and in-app
> quick log once #78 lands), show a ~5-second design-system snackbar "Logged <kind> ·
> Undo". Undo of a not-yet-pushed create removes the `PendingMutation` + `LocalEntity`
> pair locally; undo of an already-synced create queues the existing delete path. Put
> the revert logic in `LocalRepository` (e.g. `undoCreate(localID:)`) with unit tests
> for both branches; the toast itself is one overlay component in DesignComponents.
> Respect reduced motion.

## 12. In-app one-tap instant logging — [#78](https://github.com/kguy18/babybuddyios/issues/78)

> Bring the widget's one-tap logging into the app. In `DashboardView` (~lines 108–116)
> the FAB rows all open `EntityEditorView`; change Feeding and Diaper to log instantly
> using the same defaults the Quick Log widget uses (`SharedDefaults` quick-feed
> type/method; wet diaper default), with a brief confirmation. Long-press (context menu)
> keeps "Open editor…" for detail entry. Reuse the `QuickLogAction`/`QuickLogIntent`
> plumbing rather than duplicating payload construction. Settings toggle to keep the
> old open-editor behavior. Pairs with the undo toast (#77) — build that first or land
> a minimal confirmation here and adopt the toast when it exists.

## 15. Fever view: temperature curve with dose markers — [#79](https://github.com/kguy18/babybuddyios/issues/79)

> Add a fever/health chart to Trends. A Swift Charts line of cached temperature records
> over the selected window (with a denser last-72-hours focus when recent temps exist),
> a horizontal fever-threshold rule configurable in Settings (default 38.0 °C / 100.4 °F
> per the user's unit), and a point marker for each medication dose (name + dosage in
> the accessibility label / tap detail). Data: cached `/api/temperature/` and
> `/api/medication/` records, aggregation as pure tested functions in
> `ChartAggregation.swift`. Hide the card when there are no temperatures in the window.

## 18. Data-freshness stamp — [#80](https://github.com/kguy18/babybuddyios/issues/80)

> Surface sync freshness where decisions are made. Persist the last successful sync
> time (currently the in-memory `SyncEngine.lastSyncDate`, `SyncEngine.swift:13`) into
> `SharedDefaults` so both app and widgets can read it. Show "Updated X min ago" in the
> Dashboard header and `StatusWidget`, switching to the warning color past a
> configurable staleness threshold (Settings; default ~30 min, Off available). Keep the
> Settings sync row as-is. Unit-test the formatting/threshold logic with an injected
> clock.

## 19. Forgotten-timer alert — [#81](https://github.com/kguy18/babybuddyios/issues/81)

> Alert on runaway timers. When a timer starts (app, widget, or discovered via sync),
> schedule a local notification for start + threshold — per-kind defaults (e.g. feeding
> 2 h, pumping 1 h, tummy time 30 min, sleep 12 h, untyped 4 h) configurable in
> Settings, opt-in. The notification deep-links to the existing Stop sheet via
> `babybuddy://timer/<localID>` (`DeepLinkRouter`). Cancel on stop/discard; reconcile on
> sync (timer stopped from another device). Share the notification plumbing/permission
> flow with #73 if both land. Tests for schedule/cancel/reconcile with a mocked center.

## 20. Pumping & tummy time Trends cards — [#82](https://github.com/kguy18/babybuddyios/issues/82)

> Complete the Trends tab. Add two cards to `InsightsView` mirroring the existing
> patterns in `ChartAggregation.swift`: pumping volume per day (ml bars, `BBColor.pumping`,
> with session count in the accessibility label / subtitle) and tummy time minutes per
> day (`BBColor.tummyTime`). Respect the existing 7/14/30-day period control, empty
> states, and per-bar accessibility labels. Extend `ChartAggregationTests` for both
> aggregations, including a session that crosses midnight.
