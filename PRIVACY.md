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

The App Store version of this app uses [PostHog](https://posthog.com), a product-analytics service,
to understand which features are used and to catch problems. It is configured to run in an
**anonymous, privacy-respecting mode**:

- **No personal data and no baby/tracking data** is ever sent to PostHog — only generic app
  usage events together with coarse technical context such as app version, iOS version, device
  model, and locale. The events are limited to:
  - **App lifecycle** — app opened / installed / updated.
  - **Onboarding** — that sign-in completed, and whether it used the QR code or manual entry.
  - **Timers** — that a timer was started or stopped, the activity type (e.g. feeding, sleep), and
    whether it came from the app or a widget.
  - **Logged activities** — that an activity record was logged, and its kind (e.g. diaper change,
    feeding, sleep, note, measurement). Never the contents of the record.
  - **Widgets** — that a widget/Siri action was performed, and which one.
  - **Search** — that a timeline search started, completed, or returned no results.
  - **App lock** — that an unlock was attempted, the result, and the device biometry type
    (Face ID / Touch ID / none).
  - **Sync & errors** — that a sync completed or raised a conflict, and coarse error categories
    (e.g. network vs. server-rejected). Error reports never include the server's message text.
- Analytics are **not tied to your identity**. Events are attributed only to a randomly generated,
  device-scoped identifier stored on your device — the app never calls PostHog's "identify" and
  never associates events with your name, email, or account. No stable advertising identifier is
  used. Screen autocapture and session replay are disabled, so the app's contents and your
  interactions are never recorded.
- Events are sent to PostHog Cloud (US region by default). PostHog may derive an approximate
  location from your IP address for aggregate geography, as described in its privacy policy.
- Because the analytics are anonymous, there is currently **no in-app opt-out**. If you have
  concerns, you can block network traffic to PostHog or use a build that has analytics disabled
  (see below).
- See PostHog's own [privacy policy](https://posthog.com/privacy) for details on how it processes
  data.

**Open-source / self-built versions send no analytics at all.** The public source code ships without
an analytics API key, so any build you compile yourself (or a third party compiles) initializes no
analytics SDK and sends nothing to PostHog.

## In-app purchases

The App Store version uses [RevenueCat](https://www.revenuecat.com) to manage subscriptions. It only
communicates with the purchase backend when you interact with purchases, and it never receives your
baby/tracking data, your server URL, or your credentials. As with analytics, **open-source / self-built
versions ship without a RevenueCat API key**, so they initialize no purchase SDK and send nothing.
See RevenueCat's [privacy policy](https://www.revenuecat.com/privacy/) for how it processes purchase
data.

## Biometric authentication

If you enable the Face ID / passcode lock, authentication is performed by iOS via
`LocalAuthentication`. The app never receives or stores your biometric data.

## Data deletion

Sign out (Settings → Sign Out) clears the stored credentials. Deleting the app removes all locally
cached data. Records on your server are managed through Baby Buddy itself.

## Contact

For questions about this app, open an issue on the project repository.
