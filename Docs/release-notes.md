# Release notes

Two blocks per release, newest first.

- `appstore` — the "What's New in This Version" text. Paste it into App Store Connect verbatim:
  the field is plain text, so `#` and `-` appear literally — that is the convention these notes
  use, not Markdown. App Store Connect shows the version number itself, so it is never repeated
  in the text.
- `whatsnew` — the short version the app shows on first launch after an update. Written by hand,
  not derived from the block above: the store text is far too long for a card. Kept for every
  release so the app can show any of them, not only the current one.

The `whatsnew` block uses the same `#New` / `#Fixed` headers as the store block, one item per line:

    #New
    - <icon> | <title> | <body>
    #Fixed
    - <one line>

`<icon>` is one of `sync`, `alert`, `photo`, `guard`, `timer`, `widget`, `speed`, `new` — `new`
is the neutral brand glyph, for anything the others do not fit. Keep `<title>` under about 32
characters and `<body>` under about 90, or the row wraps past two lines. `<body>` may be omitted.
`#Fixed` lines are plain text with no icon and render as a green check. Splitting on `|` and
trimming is the whole parser.

The rest of the store listing (description, keywords, review information) lives in
`app_store_listing.md`, which is gitignored because it stages the reviewer's demo credentials.

## 1.4.0

```appstore
#New
- Send Feedback. Settings has a new Feedback section. From Send Feedback you can request a feature, vote on other people's ideas, see what's planned and what's shipped, or chat with me for help, all without leaving the app. Sign in with your email and a 6-digit code, no password needed. This account is only for feedback and has nothing to do with your Baby Buddy server. You can sign out, or ask me to delete it, from the Feedback Account screen.
- Running timers on the Quick Start widget. A tile whose timer is running shows a stopwatch and a green dot, whether you started it from the widget or in the app. Tapping a running tile opens that timer instead of starting a second one.
- If you have more than one child, the Quick Start widget follows the child you've selected. Its tiles show only that child's timers, and the header shows their name. The Active timer widget does the same.
- Choose your Today tiles. Settings ▸ Appearance ▸ Today tiles lets you pick which tiles show on Home and in what order: feedings, sleep, diapers, tummy time, pumping, doses, highest temperature and notes. Turn them all off to hide Today.

#Fixed
- Custom headers you paste from a website or a password manager now save. Copied text can carry invisible characters, and the app refused it with "can't contain a line break or control character". It now removes those characters for you.
- If a custom header is missing its name or its value, the error now says which header, instead of a general message.
```

```whatsnew
#New
- new | Send Feedback | Request features, vote on ideas, and chat with me for help, right in Settings.
- timer | Running timers on the widget | Quick Start tiles show a stopwatch and a dot. Tap one to open its timer.
- widget | Widgets show the selected child | Quick Start and Active timer show only that child's timers.
- new | Choose your Today tiles | Pick which tiles show on Home, and drag them into the order you want.
#Fixed
- Pasted custom headers save, even with hidden characters
- Header errors name the header that needs fixing
```

## 1.3.1

```appstore
#New
- Move an entry to another child. If you have more than one child, editing a logged activity now shows a Baby field, so you can file it under the right one. Handy with twins, when something gets logged against the wrong child in a rush. Thanks @Confituurke for the contribution!
- Overlap warning. Baby Buddy won't save two feedings, sleeps, tummy times or pumping sessions that overlap for the same child. The editor now tells you when the times you picked overlap an entry that's already logged, before you save. You can still save it.

#Fixed
- Stopping a timer now stops it on the server every time. Some servers send the same time in two different formats, and the app mistook that for a change made on another device. The entry was saved, but the timer kept running on every phone and left an entry under Settings → Conflicts. If you have one of those, tap Keep mine to finish stopping the timer. Thanks @TristanLMartin for tracking this down!
- Editing or deleting an entry no longer reports a conflict just because the server wrote its times in a different time zone.
- If someone restarts a timer before your phone has caught up, stopping it from the widget or the Live Activity now leaves their timer running, the same as stopping it in the app.
- An entry that reached the server just as the connection dropped no longer gets stuck in Pending Changes as overlapping itself. The app finds the copy the server already saved and uses that.
- If you have twins with the same birthday, the app now opens on the same child every time.
```

```whatsnew
#New
- new | Move an entry to another child | Edit a logged entry and pick a different Baby. Made for twins and multiples. Contributed by @Confituurke
- alert | Overlap warning | The editor tells you when an entry overlaps one already logged, before you save.
#Fixed
- Stopping a timer always stops it on the server
- No more false conflicts from time zone differences
- An entry saved as the connection dropped no longer gets stuck
- Twins with the same birthday open on the same child every time
```

## 1.3.0

```appstore
#New
- Move an entry to another child. If you have more than one child, editing a logged activity now shows a Baby field, so you can file it under the right one. Handy with twins, when something gets logged against the wrong child in a rush. Thanks @Confituurke for the contribution!
- Overlap warning. Baby Buddy won't save two feedings, sleeps, tummy times or pumping sessions that overlap for the same child. The editor now tells you when the times you picked overlap an entry that's already logged, before you save. You can still save it.

#Fixed
- An entry that reached the server just as the connection dropped no longer gets stuck in Pending Changes as overlapping itself. The app finds the copy the server already saved and uses that.
- If you have twins with the same birthday, the app now opens on the same child every time.
```

```whatsnew
#New
- new | Move an entry to another child | Edit a logged entry and pick a different Baby. Made for twins and multiples. Contributed by @Confituurke
- alert | Overlap warning | The editor tells you when an entry overlaps one already logged, before you save.
#Fixed
- An entry saved as the connection dropped no longer gets stuck
- Twins with the same birthday open on the same child every time
```

## 1.2.0

```appstore
#New
- Sick mode. Triggered with a fever, Home turns into a dashboard for the illness: the newest temperature, a 24-hour chart of readings and medication doses, a card per medicine with its next-dose countdown, and a timeline of what's due and what's done. Automatically suggested when a fever is recorded.
- Trends has a Temperature card. It draws every reading in the period as a curve, with your fever line dashed across it and a colored mark at each dose.
- Temperatures show one decimal in your phone's unit, °F or °C, and you can change it in Settings → Sick mode. Two phones on one server can use different units and both read every temperature correctly.
- A timer can start earlier than now. Pick a time, or tap −5, −15 or −30 min. On the Stop sheet you can correct the start time, or restart the timer if needed.
- Custom authorization headers, for a server behind an access gate such as Cloudflare Access or an nginx shared secret. Tap Advanced configuration when you sign in (experimental).

#Improved
- Stop now stops the timer the moment you tap it, on your phone and on the server. Before, the clock kept running until you saved the record. If you tap Stop by mistake, "Resume timer" carries on from the original start.
- Tapping a timer's Live Activity or its "still running" alert opens the app and leaves the timer running.

#Fixed
- Logging a timer no longer saves the moment the server received it as the end time. The End you set is the one that's kept.
- Editing an activity logged from a timer before it synced no longer brings the timer back.
- Signing in to a server behind a login proxy such as Authentik now says to let /api/ and /media/ through, instead of failing on the first sync with "Couldn't read the server response".
- An address with no Baby Buddy server behind it says so at sign-in, instead of "That record no longer exists on the server."
```

```whatsnew
#New
- new | Sick mode | Home becomes a fever dashboard: temperatures, doses, and what's due next.
- new | Fever chart in Trends | Every temperature as a curve, with a mark at each medication dose.
- timer | Start a timer earlier | Pick a start time or tap -15 min. Fix it on the Stop sheet too.
- timer | Stop means stopped | The timer stops when you tap Stop, not when you save.
- guard | Cloudflare Access support | Reach a server behind Cloudflare Access or another header gate (experimental).
#Fixed
- A logged timer keeps the End you set
- Editing an unsynced timer record no longer revives the timer
- A login failure due to a proxy at sign-in says which paths to let through
```

## 1.1.1

```appstore
#New
- Medication reminders. The medication editor has a new "Next dose after" picker, and your iPhone can tell you when the next dose is OK. The Dashboard counts down to it, and logging a dose too early shows a warning — it is a warning only, it does not stop you from logging another dose. Tapping the reminder opens a new dose already filled in. Off by default: Settings → Notifications. Each phone schedules its own reminders (only local notifications,) from synced doses, so pull to refresh before giving one.
- Forgotten timer alerts. If a timer runs past a configurable limit you choose you get a notification that opens straight to Stop Timer. Off by default: Settings → Notifications.
- Undo after logging. Every record you log shows "Undo" for five seconds, so a mis-tap at 2 a.m. is one tap to fix. You can turn it off in Settings → Quick Log.
- The Dashboard and the status widget now say when the data was last updated, and change color when it is getting old. Choose how old in Settings → Server → Stale after.
- Trends now charts tummy time (minutes per day) and pumping (amount and sessions per day).
- Home's Latest section now lists the newest medication, note and measurement as well as the five timed activities, and tapping any Latest row opens the Timeline filtered to that kind.
- A short What's New card appears the first time you open the app after an update. It is also at the top of Settings.

#Improved
- VoiceOver: the sign-out buttons, the switches in Settings and the Trends period picker now read as what they are, the lock screen keeps VoiceOver inside it, and a record the server refused says it needs attention instead of "waiting to sync".
- The app version and build number are at the bottom of Settings, for bug reports.

#Fixed
- A mistyped API token now says the token was rejected, instead of "You don't have permission to do that."
- Turning Live Activity off and straight back on no longer leaves a running timer without its banner.
- Supporter tips work again. 1.1.0 went out without its App Store purchase configuration, so the supporter screen said purchases weren't available.
```

```whatsnew
#New
- alert | Medication reminders | Set "Next dose after" and get a notification when the next dose is OK.
- timer | Forgotten timer alerts | A reminder when a timer runs too long. Turn it on in Settings → Notifications.
- new | More in Trends | Tummy time and pumping now have their own charts.
- new | Latest shows every kind | Tap a row to jump to a filtered view on the Timeline.
- new | Undo after logging | Every new record shows Undo for five seconds, so a mis-tap is one tap to fix.
- sync | Last sync time | The Dashboard and status widget show when data was last updated.
#Fixed
- Deleting a record asks first, with a cancel option
- A wrong API token says so, instead of "no permission"
- Live Activity comes back after turning it off and on
- VoiceOver reads buttons and switches by name
```

## 1.1.0

```appstore
#New
- Medication reminders. The medication editor has a new "Next dose after" picker, and your iPhone can tell you when the next dose is OK. The Dashboard counts down to it, and logging a dose too early shows a warning — it is a warning only, it does not stop you from logging another dose. Tapping the reminder opens a new dose already filled in. Off by default: Settings → Notifications. Each phone schedules its own reminders (only local notifications,) from synced doses, so pull to refresh before giving one.
- Forgotten timer alerts. If a timer runs past a configurable limit you choose you get a notification that opens straight to Stop Timer. Off by default: Settings → Notifications.
- Undo after logging. Every record you log shows "Undo" for five seconds, so a mis-tap at 2 a.m. is one tap to fix. You can turn it off in Settings → Quick Log.
- The Dashboard and the status widget now say when the data was last updated, and change color when it is getting old. Choose how old in Settings → Server → Stale after.
- Trends now charts tummy time (minutes per day) and pumping (amount and sessions per day).
- Home's Latest section now lists the newest medication, note and measurement as well as the five timed activities, and tapping any Latest row opens the Timeline filtered to that kind.
- A short What's New card appears the first time you open the app after an update. It is also at the top of Settings.

#Improved
- VoiceOver: the sign-out buttons, the switches in Settings and the Trends period picker now read as what they are, the lock screen keeps VoiceOver inside it, and a record the server refused says it needs attention instead of "waiting to sync".
- The app version and build number are at the bottom of Settings, for bug reports.

#Fixed
- A mistyped API token now says the token was rejected, instead of "You don't have permission to do that."
- Turning Live Activity off and straight back on no longer leaves a running timer without its banner.
```

```whatsnew
#New
- alert | Medication reminders | Set "Next dose after" and get a notification when the next dose is OK.
- timer | Forgotten timer alerts | A reminder when a timer runs too long. Turn it on in Settings → Notifications.
- new | More in Trends | Tummy time and pumping now have their own charts.
- new | Latest shows every kind | Tap a row to jump to a filtered view on the Timeline.
- new | Undo after logging | Every new record shows Undo for five seconds, so a mis-tap is one tap to fix.
- sync | Last sync time | The Dashboard and status widget show when data was last updated.
#Fixed
- Deleting a record asks first, with a cancel option
- A wrong API token says so, instead of "no permission"
- Live Activity comes back after turning it off and on
- VoiceOver reads buttons and switches by name
```

## 1.0.3

```appstore
#New
- Sync problems are now visible. A record the server refuses stops retrying and shows up in Settings → Pending Changes with the server's reason in plain words, plus Retry and Discard.
- Records that could not sync show a red warning next to the sync icon on the Timeline. Open one and the reason appears at the top; tap it to jump straight to Pending Changes.
- Queued photo uploads now appear in Pending Changes too.
- Logging a pumping session without an amount, or an activity that ends before it starts, runs over 24 hours, or is set in the future, is caught before you save.

#Fixed
- Repeating a feeding from the Timeline no longer leaves the old end time behind, which made the copy fail to sync.
- Child photos now upload correctly to the server.
- Stopping a timer that was already stopped elsewhere no longer retries forever, and never creates a duplicate on its own.
- Tag lists from some server versions now sync instead of failing.
```

```whatsnew
#New
- sync | Sync problems are visible | Rejected records stop retrying and wait in Pending Changes with the reason.
- alert | Flagged on the Timeline | Records that failed to sync show a red warning. Tap it to see why.
- photo | Photo uploads queue too | Queued child photos now appear in Pending Changes as well.
- guard | Caught before you save | Missing amounts and impossible times are flagged as you log them.
#Fixed
- Repeating a feeding keeps the right end time
- Child photos upload to the server correctly
- Stopping a timer twice can't create a duplicate
- Tag lists from older servers sync again
```

## 1.0.2

```appstore
#New
- Sync and sign-in failures now report more detail, so I can find problems that only happen on certain Baby Buddy server versions. Still anonymous.
- If a sync fails for you, please let me know roughly when — these reports should make it findable.

#Fixed
- Connection problems now say what actually failed. A wrong address, a server that is not on your network, and a certificate your iPhone does not trust used to all show the same "no connection" message.
```

```whatsnew
#New
- sync | More detail on failures | Sync and sign-in errors now report what actually went wrong. Still anonymous.
#Fixed
- Connection problems say what failed, not just "no connection"
```

## 1.0.1

```appstore
#New
- Performance improvements for older devices.
- Scrolling the Timeline, switching tabs, and searching should all feel noticeably smoother.
- Please try it on your device and let me know if you still see any lag — and where.

#Fixed
- When signing out the local cache now clears, this fixes the issue with persisted data from prior servers which would make no sense.
- Widgets clear on logout and do not hold stale data.
- Sign out popup now appears with the option to cancel.
```

```whatsnew
#New
- speed | Faster on older devices | Timeline scrolling, switching tabs and searching all feel smoother.
#Fixed
- Signing out clears the local cache
- Widgets clear on logout instead of holding stale data
- Sign out asks first, with a way to cancel
```

## 1.0

```appstore
The first release of Baby Buddy Companion. Track feedings, sleep, diapers, pumping, and growth on your self-hosted Baby Buddy server — offline-first, with live timers and Home Screen widgets. Thanks for trying it!
```

```whatsnew
#New
- new | Welcome to Baby Buddy | Track feedings, sleep, diapers, pumping and growth on your own server.
- timer | Live timers and widgets | Start a timer anywhere and see it on the Home Screen.
- sync | Works offline | Everything you log syncs when the server is reachable again.
```
