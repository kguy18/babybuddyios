# Growth charts

Trends previously queried sleep, feeding, changes, tummy time, pumping, temperature and
medication. Weight, height and head circumference were already cached and synced, but were
not part of that query or rendered as charts. This feature adds three native Swift Charts
cards and read-only measurement details. It is independent of the German localization PR #206.

## Data and units

- Existing `/api/weight/`, `/api/height/` and `/api/head-circumference/` records are read from
  `LocalEntity`. These collections are already pulled in full, so the growth period can be
  30 days, 90 days, one year, or all history without additional requests.
- Each point is a real record. No missing-day zeroes, averages, inferred measurements or
  smoothed patient values. Multiple readings on the same date remain available in details.
- Deleted records, nonfinite/nonpositive values, malformed dates and future dates are excluded.
  Unsynced local creates and edits are displayed, as elsewhere in the app.
- Date-only payloads are parsed as Gregorian calendar dates in the display time zone; they
  are not converted from UTC midnight into the previous day. Periods and age use calendar-day
  arithmetic, including daylight-saving changes and leap days.
- The API's measurement payloads contain bare numbers, without unit metadata. Initially the
  chart shows recorded values. The user explicitly confirms source weight units (kg, g or lb)
  and source length units (cm or in) before any metric label or WHO comparison appears.
  Weight can then be shown in kg or g, and lengths in cm. Conversion is for display only:
  1 lb = 0.45359237 kg, 1 in = 2.54 cm, 1000 g = 1 kg. No API payload is rewritten.
- The y axis includes the visible measurements and reference curves, with padding and a
  nonzero span for a single or constant reading. The x axis covers the selected window.

## Optional WHO references

The bundled data are WHO Child Growth Standards, **expanded daily percentile tables**:

- [Weight-for-age](https://www.who.int/tools/child-growth-standards/standards/weight-for-age)
- [Length/height-for-age](https://www.who.int/tools/child-growth-standards/standards/length-height-for-age)
- [Head circumference-for-age](https://www.who.int/tools/child-growth-standards/standards/head-circumference-for-age)
- [WHO technical instructions for reproducing the charts](https://cdn.who.int/media/docs/default-source/child-growth/child-growth-standards/indicators/instructions-en.pdf?sfvrsn=5cec8c61_23)

The six tables cover girls and boys, ages 0–1856 days inclusive. Each imported row retains
the published LMS coefficients and P3/P15/P50/P85/P97 values. Curves plot the **published
daily centiles directly**, not an estimated percentile calculated from a child's readings.
Long-range rendering samples the older part of each reference curve to bound chart marks;
the first 90 days, visible endpoints, and days 730/731 are always retained. Every rendered
vertex is a published daily centile, joined linearly. All daily source rows remain bundled.
No values are extrapolated outside the table range. Length and standing-height reference
series are disconnected between days 730 and 731, as required by WHO's technical notes.
The app makes no automatic posture adjustment to a recorded measurement.

The API child profile exposes birth date, but not reference sex, gestational age or due date.
WHO comparisons therefore start off. Settings require an explicitly chosen reference,
confirmed source units and an age basis. Chronological age must be selected explicitly.
Corrected age is available only when the user supplies an expected due date from a medical
record and confirms its source; the date must be after birth. Corrected age is the number
of calendar days since that documented due date. Before the due date, curves stay hidden.
There is no inferred prematurity, default gestational age, or automatic correction cutoff.
The user and care team choose whether correction is appropriate. Length overlays also
require confirmation that readings use recumbent length through day 730 and standing height
from day 731 on the chosen age basis.

These are reference curves for context, without diagnosis, normal/abnormal labels, alerts or
individual percentile classification. They do not replace an individual assessment.

Reference choices and documented due date stay in device-local preferences, separately for
each child. Cache wipe on sign-out or a server change clears those new preferences, preventing
another server's child with the same integer ID from inheriting them. No new telemetry,
network calls, schema migration, synchronization behavior, or installation changes are added.

## Provenance and reproduction

`Sources/Resources/who-growth-reference.json` includes each official XLSX download URL and
its original SHA-256. Source files were retrieved on 2026-10-27. WHO is the source of the
reference data; the app does not imply WHO endorsement. The original reference material
remains WHO material and is not relicensed by the application's code license. See the WHO
technical instructions for the source disclaimer and [WHO permissions](https://www.who.int/about/policies/publishing/copyright).

To reproduce the generated resource, download the six XLSX files at the URLs stored in
the JSON to one directory, then run:

```sh
python3 scripts/import-who-growth.py /path/to/who-xlsx-files
```

The importer uses only Python's standard library. It never downloads files or sends data.
It verifies complete ages 0–1856 for every table and selects columns by header name.

## Localization

All 46 feature strings have English and German translations in the dedicated
`Growth.xcstrings` table. Native number/date formatting follows the device locale.
The feature does not modify the shared string catalog or require PR #206 to be merged.
Other screens retain their upstream language behavior until that separate PR lands.

## Verification

`scripts/test-growth-core.sh` compiles the actual Foundation sources with a standalone
assertion harness. It needs Swift and Foundation, not XCTest or an iOS SDK. It checks:

- All 55,710 published centiles against the corresponding LMS coefficients, using standard
  normal quantiles for P3, P15, P50, P85 and P97. Tolerance is 0.001 kg/cm, allowing the WHO
  tables' three-decimal centile rounding; observed maximum deviation is 0.0005 kg/cm.
- Independent birth-row examples for all three metrics and both sexes transcribed from the
  official monthly percentile PDF tables linked from the three WHO pages above. Those PDFs
  use one decimal, so that comparison allows 0.051 kg/cm.
- Date-only handling, DST, leap days, non-Gregorian user calendars, missing/invalid data,
  child isolation, period boundaries, same-day readings, axes, unit conversions, required
  reference data, documented corrected age and preference cleanup.

There are also 20 new XCTest methods, an extended sign-out cleanup test, and five new
XCUITest methods for cards/details, units, periods, empty states, child switching and German.
The UI class is included in the existing CI shard matrix.

Local checks passed: the standalone core checks (55,988 assertions), 49 existing Node tests,
release-note validation, string completeness, UI shard coverage, XcodeGen generation,
project plist validation, Swift syntax parsing and `git diff --check`.

**Not run locally:** an iOS app/widget build, hosted XCTest, XCUITest, simulator/device
rendering, accessibility audit, or live-server integration. The machine has Apple Command
Line Tools and Swift, but no full Xcode/iOS SDK; `xcodebuild -version` reports that Xcode is
required. The Foundation harness does not verify SwiftUI/Charts compilation or rendering.

## Maintainer device checklist

- [ ] Build app and widgets with Xcode on iOS 17 and current iOS, and run unit/UI suites.
- [ ] Compare metric and gram display against the same records on a test server; check source
  units before enabling reference curves. Verify an imperial-source test dataset too.
- [ ] Try one point, several points on one date, no points, each period, all history, offline
  use, a second child, record edits and deletion, and sign-out/server change cleanup.
- [ ] Enable each WHO reference, compare the rendered lines with official tables, and inspect
  the day 730/731 break. Check missing birth date, unsupported ages and documented due date.
- [ ] Check small screens, light/dark appearance, large text, VoiceOver, chart selection,
  measurement details, and English/German number/date formatting.
