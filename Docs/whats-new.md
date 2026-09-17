---
version: 1.1.0
title: What's New
---

# What's New — the screen's copy

**This file is the screen.** It ships inside the app and is read at launch, so editing the
copy here and rebuilding is all it takes — no Swift changes. Everything above the first
`##` heading, including this paragraph and the rules below, is ignored by the parser: write
whatever notes you like up here, but never between the rows.

The rules:

- The `---` block at the very top sets `version` and `title` for the whole screen.
  `version` is the release these notes describe. **The screen only appears when it matches
  `MARKETING_VERSION` in `project.yml`** — which is `1.0.3` today, so this screen stays
  dormant until you bump to `1.1.0` for the release. `BB_WHATS_NEW=1` forces it on in a
  debug build regardless.
- Each `##` heading is one row, and the heading text is the row's title. Keep it to three
  or four words — it sits on one line next to the icon. There are no other `##` headings in
  this file for exactly that reason.
- `Icon:` is an SF Symbol name. `Tint:` is one of `brand`, `success`, `warning`, `danger`,
  `info`, `feeding`, `sleep`, `tummy`, `pumping`, `note` — all from the design system, so
  they are correct in dark mode for free.
- Everything else under a heading is the blurb, and wrapped lines are rejoined into one
  sentence. `Icon:` and `Tint:` are the only field names; a sentence that happens to start
  with some other word and a colon stays part of the blurb.
- Aim for three to five rows. More than five and the sheet starts scrolling, which is the
  point at which it stops feeling like a sheet.
- If anything here is malformed — an unknown tint, a row with no blurb, no rows at all —
  the app shows **no** What's New screen rather than a broken one. `WhatsNewParsingTests`
  parses this exact file on every CI run, so a typo fails the build instead of shipping
  silently.

Everything below is a first draft, written from the issue descriptions. It is meant to be
rewritten.

## Next-dose reminders

Icon: pills.fill
Tint: danger

Log a medication with an interval and your phone tells you when the next dose is allowed.

## Forgotten-timer alerts

Icon: timer
Tint: tummy

A timer left running past your threshold now taps you on the shoulder, and opens straight
to the Stop sheet.

## Undo any log

Icon: arrow.uturn.backward
Tint: brand

Every record you log now shows a five-second Undo, so a mis-tap is one tap to fix.

## Freshness stamp

Icon: clock.arrow.circlepath
Tint: success

The Dashboard and the status widget now say when they last synced, and turn amber when
that goes stale.

## Pumping and tummy time in Trends

Icon: chart.bar
Tint: info

Pumping volume per day and tummy-time minutes per day join the 7, 14 and 30-day windows.
