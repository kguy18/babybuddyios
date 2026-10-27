# What's next: local estimates

Implements the next-feed estimate requested in #74, with optional next-nap, possible wake-up
and diaper-logging pattern cues. It does not reproduce Baby Tracker's proprietary algorithm.

## Calculation

- Read-only, selected-child records from the existing cache. No new API, tracking or sync calls.
- The trailing 14 days, at most ten observations per cue, at least four observations across
  three distinct local calendar days. Historical anchors must be within three local clock
  hours of the current anchor. These are configurable-in-code heuristics, not clinical norms.
- Feeding: consecutive completed feeding starts. All feeding types are included; mixed or
  changing routines can suppress estimates. No artificial merging of cluster feeds.
- Next nap: previous sleep **end** to the next explicitly marked nap's **start**. The current
  anchor is the last completed sleep's end. Unknown nap flags are not guessed.
- Possible wake-up while a sleep timer runs: previous completed sleep durations beginning at
  similar local clock times. A generic sleep timer does not identify nap/night, so matching
  uses observed start context rather than a guessed nap flag. Typical nap duration is also
  shown when matching marked naps provide enough evidence.
- Diaper: times of logged changes, labeled as a logging pattern, not an estimate of biological
  need or a recommended waiting interval.
- The center is the median. The displayed descriptive window is P20–P80 plus padding of
  max(5 min, 10% of the median). It is **not a calibrated confidence interval**. Suppress when
  MAD/median > 0.35 or IQR/median > 0.65. No age-based feeding/wake schedules are used.
- Ignore exact duplicate intervals, pending deletion, future starts, old history and invalid
  historical pairs. Invalid or conflicted latest entries suppress that cue. Overlapping
  sessions are not used as interval evidence. No pair bridges an incomplete historical entry.
  The 24-hour sample bound avoids treating multi-day logging gaps as a routine.
- Active or stopped-but-unlogged timers suppress the corresponding next-activity estimate;
  an unclassified timer suppresses all cues. A running sleep may produce a wake-up estimate.
- Require a successful sync within two hours. Recently synced cached data works offline;
  stale or unknown cache freshness suppresses numeric estimates. A passed window never rolls
  forward into a new prediction and is not labeled overdue.

The feature starts off. Settings > Activity estimates enables the Home card and a compact
line on the medium status widget. The Dashboard recomputes each minute. Widget timelines
include an explicit expiry entry to remove predictions at their end/freshness cutoff even
when WidgetKit delays its refresh. Other widget families keep their original layout.
English and German feature strings are in the dedicated `Forecast.xcstrings` table,
included in both app and widget bundles. Existing timestamps and today's counts are unchanged;
the separate display-semantics report #208 is not silently changed by this feature.

## Verification and limits

`scripts/test-forecast-core.sh` compiles the actual Foundation engine and formatter with a
standalone assertion harness. XCTest is not needed for these checks. Supplied XCTest cases
cover starts versus ends, sparse/irregular evidence, stale sync, child isolation, duplicates,
deletions, conflicts, timers, old history and quantiles. UI tests cover enable/disable,
off-by-default behavior and child switching. `BB_SEED_FORECAST=1` supplies a synthetic demo
routine; no server credentials or real family records are used.

No accuracy claim or clinical validation is made. Missing logs, rapidly changing routines,
and uncertain nap flags limit these descriptive estimates. An optional provider-backed
comparison can build on this interface, but it must not bypass evidence/freshness gates.

Local environment: macOS with Swift and Command Line Tools, without full Xcode/iOS SDK.
Foundation checks, syntax parsing, project generation and script checks can run here.
The iOS app/widget build, XCTest host, XCUITest and device rendering have **not** been run.

## Maintainer device checklist

- [ ] Build app and widgets on iOS 17/current iOS; run unit/UI suites.
- [ ] Enable estimates, inspect typical records, incomplete entries, variable routines and
  another child; confirm no records or sync payloads change.
- [ ] Check nap anchors against sleep end, a running sleep timer's wake cue, and a stopped
  timer waiting to be logged. Inspect midnight/DST cases in the device time zone.
- [ ] Check the medium widget's space, expiry, large text, VoiceOver and German formatting.
