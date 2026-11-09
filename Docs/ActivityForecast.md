# Activity estimates: local estimates

Implements the next-feed estimate requested in #74, with next-nap, possible wake-up, and
diaper-logging pattern cues. It does not reproduce Baby Tracker's proprietary algorithm.

## Calculation

- Read-only, selected-child records from the existing cache. No new API, tracking or sync calls.
- The trailing 14 days, at most ten observations per cue, at least four observations across
  three distinct local calendar days. Historical anchors must be within three local clock
  hours of the current anchor. These are configurable-in-code heuristics, not clinical norms.
- Feeding: consecutive completed feeding starts. All feeding types are included; mixed or
  changing routines can suppress estimates. No artificial merging of cluster feeds.
- Next nap: previous sleep **end** to the next explicitly marked nap's **start**. The current
  anchor is the last completed sleep's end. Unknown nap flags are not guessed. Most of the last
  ten similar-time wake-ups must have been followed by a marked nap. Otherwise the cue is
  insufficient, so no nap is predicted after the day's last nap. With three naps a day the
  three-hour match holds one wake-up that led to a nap and one that led to the night, which
  is not a majority. A routine with naps closer together can still pass after the last one.
- Possible wake-up while a sleep timer runs: previous completed sleep durations beginning at
  similar local clock times. A generic sleep timer does not identify nap/night, so matching
  uses observed start context rather than a guessed nap flag.
- Diaper: times of logged changes, labeled as a logging pattern, not an estimate of biological
  need or a recommended waiting interval.
- The center is the median. The displayed descriptive window is P20–P80 plus padding of
  max(5 min, 10% of the median). It is **not a calibrated confidence interval**. Suppress when
  MAD/median > 0.35 or IQR/median > 0.65. No age-based feeding/wake schedules are used.
- Ignore exact duplicate intervals, pending deletion, future starts, old history, and invalid
  historical pairs. Invalid or conflicted latest entries suppress that cue. An older conflicted
  entry only loses the pairs it belongs to. Overlapping sessions are not used as interval
  evidence. No pair bridges an incomplete or conflicted historical entry.
  The 24-hour sample bound avoids treating multi-day logging gaps as a routine.
- Active or stopped-but-unlogged timers suppress the corresponding next-activity estimate;
  an unclassified timer suppresses all cues. A running sleep may produce a wake-up estimate.
- Require a successful sync within two hours. Recently synced cached data works offline;
  stale or unknown cache freshness suppresses numeric estimates. A passed window never rolls
  forward into a new prediction and is not labeled overdue.

## Where estimates show

The feature starts off. The switch is on Settings > Appearance > Activity estimates, which
also holds the disclaimer and how the estimates work.

On Home each estimate is a footer on its Today tile: Feedings "Next", Sleep "Nap" or, while a
sleep timer runs, "Wakes", and Diapers "Next". The time is `~` plus the window's midpoint. Only
a ready cue shows, so an elapsed, irregular, stale, or insufficient cue leaves the tile as it
was. A hidden tile hides its estimate, sick mode's fixed grid has no footers, and VoiceOver
reads the estimate after the tile's value. The Dashboard recomputes each minute.

The medium status widget has a compact line with the first ready estimate's window. Widget
timelines include an explicit expiry entry to remove estimates at their end or freshness cutoff
even when WidgetKit delays its refresh. Other widget families keep their original layout.

Times within the next 24 hours show no date, including a window after midnight.

English, German, and Brazilian Portuguese feature strings are in the dedicated
`Forecast.xcstrings` table, included in both app and widget bundles. Existing timestamps and
today's counts are unchanged; the separate display-semantics report #208 is not silently
changed by this feature.

## Verification and limits

`scripts/test-forecast-core.sh` compiles the actual Foundation engine and formatter with a
standalone assertion harness. XCTest cases cover starts versus ends, sparse and irregular
evidence, stale sync, child isolation, duplicates, deletions, conflicts, timers, old history,
quantiles, the nap majority, and date formatting. UI tests cover the tile footers, the setting,
off-by-default behavior, localization, and child switching. `BB_SEED_FORECAST=1` supplies a
synthetic routine; no server credentials or real family records are used.

No accuracy claim or clinical validation is made. Missing logs, rapidly changing routines,
and uncertain nap flags limit these descriptive estimates. An optional provider-backed
comparison can build on this interface, but it must not bypass evidence or freshness gates.
