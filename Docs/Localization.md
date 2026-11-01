# Localization

The app ships in English and German (`de`). iOS selects the language from the system
preferences or the system's per-app language setting. There is no language override in the app.

English is the development language and the only required one. Every key needs English text.
Other languages are optional: a key with no translation shows in English, and a missing
translation never fails CI.

`Sources/Shared/Localizable.xcstrings` is the one catalog for the app and the widget extension;
both targets include `Sources/Shared` in `project.yml`. Feature work adds its keys there rather
than creating new tables. The catalog covers the native UI, accessibility labels,
client-generated errors, local notifications, App Intents, widget configuration, Live Activities,
and the bundled What's New cards. `Sources/Resources/InfoPlist.xcstrings` localizes the camera
and Face ID permission descriptions in the app bundle.

Use native SwiftUI localization for literals. Use `String(localized:)` when passing a plain
`String` to a custom component or returning a display label. Translate complete sentences and
use catalog plural variants rather than assembling English suffixes. Feeding-picker labels
have separate short keys where context matters: solid food is "Beikost", while a solid diaper
contains "Stuhlgang".

The What's New view passes the titles, bodies and fixes parsed from the bundled English release
notes to `NSLocalizedString`. A line with a catalog entry shows translated; a line without one
shows in English, so a release never has to wait for translations. Catalog entries are marked
manual so building either target keeps shared strings and older bundled notes.

API enum raw values, paths, payload keys, stored timer names, and custom user content retain
their original values. Built-in timer names and known feeding/diaper choices are localized at
display time. Server-provided messages and the externally hosted feedback interface retain the
language supplied by those services. Localizing this client does not translate the server.

Dates and times use Foundation formatting. Decimal display follows the current region, including
the German decimal comma; the editor already accepts comma and period input. Displaying a
translated unit never changes a stored value or its unit.

## Adding or updating a language

- In Xcode, open `Localizable.xcstrings` and `InfoPlist.xcstrings`, add the language with "+" at
  the bottom of the language list, and translate in the catalog editor. Run `xcodegen generate`
  afterwards; it picks the new language up from the catalogs.
- Or work in XLIFF: `xcodebuild -exportLocalizations -project BabyBuddy.xcodeproj
  -localizationPath <dir> -exportLanguage <lang>` writes a `.xcloc` bundle to translate, and
  `xcodebuild -importLocalizations -project BabyBuddy.xcodeproj -localizationPath <lang>.xcloc`
  merges it back into the catalogs.
- Translate whole sentences, keep every `%@` and `%lld` (reordered with `%1$@` if needed), and
  give plurals at least an `other` form.

`python3 scripts/check-localization.py` prints each language's coverage, for example
`de: 100%, 0 missing`; CI adds the same lines to the job summary.
`python3 scripts/check-localization.py --missing <lang>` lists the keys a language still lacks.

## Validation

```sh
python3 scripts/check-localization.py
node --test scripts/*.test.mjs
node scripts/release.mjs validate
xcodegen generate
```

The catalog check fails only when English text is missing, `project.yml` no longer gives the
widget the shared catalog, or an existing translation is empty, lacks an `other` plural form, or
changes an argument's position or type. It runs in the PR workflow. `LocalizationTests`
checks the compiled resources, language selection, English fallback, plurals, reordered
arguments and stable payload values. `GermanLocalizationTests` launches the app with German
language and region settings; the existing UI suite continues to run in English.

With Xcode and an iOS 26+ simulator, run the unit scheme and `scripts/ui-test.sh` as described in
[DEVELOPMENT.md](DEVELOPMENT.md). These checks require Xcode; Swift syntax parsing alone does
not establish an iOS build or a passing XCTest run.

## Manual device review

- Choose German in iOS and open onboarding, Home, Timeline, Trends and Settings. Check narrow
  screens, larger text sizes and VoiceOver for truncation or untranslated client text.
- On an open iPhone Duo, check the Today timeline pane and its empty state. Fold the device,
  then open a Today tile and its add button; both layouts should keep their German labels.
- Add and edit a feeding with both breast and bottle methods, a diaper change, sleep and
  pumping. Enter a decimal comma and verify the saved amount. Check that solid food reads
  "Beikost" and a diaper containing stool reads "Stuhlgang".
- Start and stop each timer. Check the widget gallery, Quick Start, Quick Log, status widgets,
  Lock Screen accessories, Live Activity and Dynamic Island. Custom timer names stay intact.
- Check forgotten-timer alerts, medication and temperature reminders, error messages,
  conflicts, pending changes and the two permission prompts. Use synthetic data.
- Choose English and an unsupported system language to check the English fallback. Review
  the What's New card in both supported languages.
