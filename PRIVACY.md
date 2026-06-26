# Privacy Policy — Baby Buddy for iOS

_Last updated: 2026-06-25_

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
  - **Widgets** — that a widget/Siri action was performed, and which one.
  - **Search** — that a timeline search started, completed, or returned no results.
  - **App lock** — that an unlock was attempted, the result, and the device biometry type
    (Face ID / Touch ID / none).
  - **Sync & errors** — that a sync completed or raised a conflict, and coarse error categories
    (e.g. network vs. server-rejected). Error reports never include the server's message text.
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

## Biometric authentication

If you enable the Face ID / passcode lock, authentication is performed by iOS via
`LocalAuthentication`. The app never receives or stores your biometric data.

## Data deletion

Sign out (Settings → Sign Out) clears the stored credentials. Deleting the app removes all locally
cached data. Records on your server are managed through Baby Buddy itself.

## Contact

For questions about this app, open an issue on the project repository.
