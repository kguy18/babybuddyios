# Privacy Policy — Baby Buddy for iOS

_Last updated: 2026-06-18_

Baby Buddy for iOS is a client for a **self-hosted Baby Buddy server that you provide**. The app has
no first-party backend operated by the developer.

## What the app stores

- **On your device:** your child and tracking data is cached locally (SwiftData) so the app works
  offline. Your server URL and API token are stored in the iOS Keychain
  (`WhenUnlockedThisDeviceOnly` — they never leave the device or sync to iCloud).
- **On your server:** all tracking data is sent to and read from the Baby Buddy server you configure.
  How that server handles your data is governed by your own deployment.

## What the app sends, and to whom

- Network requests go **only** to the server URL you enter. Nothing is sent to the developer or any
  third party.
- There are **no analytics, advertising, or tracking SDKs** in the app.

## Biometric authentication

If you enable the Face ID / passcode lock, authentication is performed by iOS via
`LocalAuthentication`. The app never receives or stores your biometric data.

## Data deletion

Sign out (Settings → Sign Out) clears the stored credentials. Deleting the app removes all locally
cached data. Records on your server are managed through Baby Buddy itself.

## Contact

For questions about this app, open an issue on the project repository.
