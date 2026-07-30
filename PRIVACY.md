# Privacy Policy — Baby Buddy for iOS

_Last updated: 2026-07-30_

Baby Buddy for iOS is a client for a **self-hosted Baby Buddy server that you provide**. The app has
no first-party backend operated by the developer.

## What the app stores

- **On your device:** your child and tracking data is cached locally (SwiftData) so the app works
  offline. Your server URL and API token are stored in the iOS Keychain
  (`WhenUnlockedThisDeviceOnly` — they never leave the device or sync to iCloud).
- **On your server:** all tracking data is sent to and read from the Baby Buddy server you configure.
  How that server handles your data is governed by your own deployment.

## What the app sends, and to whom

- Your tracking data (children, feedings, sleep, etc.) goes **only** to the Baby Buddy server URL
  you enter. None of your tracking data, your server URL, or your credentials are ever sent to the
  developer or any third party.
- The App Store build includes a small amount of **anonymous, non-attributed usage analytics** — see
  below. There is **no advertising and no cross-app tracking**.

## Analytics

The App Store version of this app uses [TelemetryDeck](https://telemetrydeck.com), a privacy-focused,
cookieless analytics service, to understand which features are used and to catch problems. It is
designed to be **anonymous and non-attributed**:

- **No personal data and no baby/tracking data** is ever sent to TelemetryDeck — only generic app
  usage signals together with coarse technical context such as app version, iOS version, device
  model, and locale. The usage signals are limited to:
  - **App lifecycle** — app launched / session started, and new-install detection.
  - **Onboarding** — that sign-in completed, and whether it used the QR code or manual entry.
  - **Timers** — that a timer was started or stopped, the activity type (e.g. feeding, sleep), and
    whether it came from the app or a widget.
  - **Logged activities** — that an activity record was logged, its kind (e.g. diaper change,
    feeding, sleep, note, measurement), and which path created it (a form, a "repeat", stopping a
    timer, or a widget/Siri action). Never the contents of the record.
  - **Widgets** — that a widget/Siri action was performed, and which one.
  - **Search** — that a timeline search started, completed, or returned no results.
  - **Trends** — that the Trends tab was opened, and which rolling window was selected (7, 14, or
    30 days). Never any of the figures shown on it.
  - **App lock** — that an unlock was attempted, the result, and the device biometry type
    (Face ID / Touch ID / none).
  - **Sync & errors** — that a sync completed, that a conflict was raised, and that a conflict was
    resolved together with which way it was settled (keep mine / use server / merge) and the record
    kind; plus coarse error categories (e.g. network vs. server-rejected). Neither the local nor the
    server version of a conflicted record is ever included, and error reports never include the
    server's message text.
  - **Supporter tips** — that the supporter sheet was viewed, which entry point opened it (Settings,
    a link, or one of the support nudges below), and whether it was showing the ask, the thank-you,
    or a notice that tips are unavailable; that a supporter reopened the amounts ("Tip again"); and
    the coarse outcome of an optional tip (started, completed, cancelled, failed, or restored) and
    that supporter status became active, together with the tip's size band (small / medium /
    large). A completed tip and a sheet view also
    carry the name of the store "offering" that served them — a label configured by the developer,
    not anything about you. These carry only a coarse status/error code, a size band, a sheet state,
    an offering name, and an entry-point name — never price, receipt, customer, or transaction
    details.
  - **Support nudges** — that a nudge inviting you to support the app was shown, dismissed, or
    retired; which of its three variants it was; how many times nudges have been dismissed; and, for
    a milestone nudge, the round threshold that triggered it (50 / 100 / 250 / 500 / 1000 records
    logged on this device). Never what was logged — only how many.
  - **Settings** — that a named setting was switched on or off. Carries the setting's name and the
    new on/off value only, never the data the setting affects.
- Analytics are **not tied to your identity**. TelemetryDeck does not use cookies or stable
  advertising identifiers; any user count is derived from a one-way, non-reversible hash and cannot
  be traced back to you. Your IP address is not stored.
- Because the analytics are fully anonymous, there is currently **no in-app opt-out**. If you have
  concerns, you can block network traffic to TelemetryDeck or use a build that has analytics
  disabled (see below).
- See TelemetryDeck's own [privacy policy](https://telemetrydeck.com/privacy/) for details on how it
  processes data.

**Open-source / self-built versions send no analytics at all.** The public source code ships without
an analytics App ID, so any build you compile yourself (or a third party compiles) initializes no
analytics SDK and sends nothing to TelemetryDeck.

## In-app purchases

Every feature in the app is free. The App Store version uses
[RevenueCat](https://www.revenuecat.com) to manage the optional one-time supporter tips — there is no
subscription. It contacts the purchase backend when the app starts and when you open the supporter
screen — to fetch the tip amounts on offer and how that screen should be presented — and when you
actually tip or restore a purchase. It never receives your
baby/tracking data, your server URL, or your credentials. As with analytics, **open-source / self-built
versions ship without a RevenueCat API key**, so they initialize no purchase SDK and send nothing.
See RevenueCat's [privacy policy](https://www.revenuecat.com/privacy/) for how it processes purchase
data.

In the App Store version, RevenueCat forwards its purchase events (e.g. a purchase, renewal, or
refund) to TelemetryDeck on the server side so they appear alongside the analytics above. These are
keyed only by the same anonymous, salted per-device hash used for analytics — never your Apple ID,
receipt, or any identifying detail. This forwarding cannot happen in open-source / self-built
versions, which ship without either a RevenueCat key or an analytics App ID.

## Biometric authentication

If you enable the Face ID / passcode lock, authentication is performed by iOS via
`LocalAuthentication`. The app never receives or stores your biometric data.

## Data deletion

Sign out (Settings → Sign Out) clears the stored credentials. Deleting the app removes all locally
cached data. Records on your server are managed through Baby Buddy itself.

## Contact

For questions about this app, open an issue on the project repository.
