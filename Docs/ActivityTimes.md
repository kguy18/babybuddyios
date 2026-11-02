# Last activity times

Home's Latest rows and all status-widget families now distinguish the end of a saved feeding or
sleep from its start. A sleep from 12:00 to 13:00 reads as waking 30 minutes ago at 13:30, and a
feeding ending at 13:30 reads as finished two minutes ago at 13:32.

`ActivityRecency` chooses a presentation date and its meaning. Only a parseable start/end pair
with end >= start and end <= now establishes completion. Missing, malformed, reversed or future
ends explicitly use a Started/Feed started/Sleep started fallback. Zero-length sessions are valid.
Other activity kinds retain their canonical event time.

The most recent relevant end wins when older-starting sessions overlap newer-starting ones.
The Dashboard and widget share this selection rule. Timeline sorting and rows, stored payloads,
canonical timestamps, session durations, day counts, API requests and synchronization are unchanged.
Overnight sessions still count on their original start day. Each child's status uses its own records.

For the widget, a newer typed feeding/sleep timer shows Feeding/Sleeping and counts from its start.
A stopped draft shows Feed stopped/Sleep stopped until it is saved, resumed or discarded; it does
not silently become a completed feeding or an Awake status. Stopped drafts remain visible while
their server DELETE is queued. Unknown/custom timers without an activity hint keep the existing
generic timer header and do not invent a feeding or sleep status.

Labels and spoken time descriptions live in the separate English/German `ActivityTimes` catalog,
shared by the app and widgets. The fix can be reviewed independently of localization PR #206.
Latest-row VoiceOver describes the same end/start basis as the visual row. The generic timeline
accessibility formatter retains its original start-time behavior.

## Validation

`scripts/test-activity-recency.sh` compiles the actual Foundation presentation helper and checks
completed sessions, fallback cases, timers, other kinds, midnight and both DST boundaries.
`ActivityRecencyTests` and `CompletedActivityStatusTests` cover the helper, compiled translations,
latest-end selection, child scoping, unchanged timestamps/payloads/day totals and stopped drafts.
The added `DashboardTests` flow verifies end-based Latest labels and unchanged timeline semantics.

The standalone checks do not compile the iOS app, WidgetKit views or SwiftData models. Those tests
and a device review require full Xcode; they must not be represented as passed on a CLI-only host.

## Device review

- Save synthetic feeding and sleep intervals with distinct start/end times. Home and every status
  widget size should name the end-based time. Check VoiceOver, German and large text.
- Try missing, invalid and future ends. The display should identify its start fallback.
- Start, stop without saving, resume and discard typed feeding/sleep timers. Awake must not keep
  counting while a newer sleep timer is running, and stopping must not add to today's saved count.
- Edit a backdated session, cross midnight and switch children. Check the corrected latest time,
  unchanged duration/day totals and original timeline ordering. Widget updates follow the existing
  WidgetKit refresh policy; compact medium-widget ages retain the existing refresh granularity.
