# iPhone release preparation

The release target is iPhone first, with iOS 18.6 as the minimum for both the app and its
share extension. Code and packaging checks do not replace a signed physical-device release
check. No upload or distribution signing is performed by the verification script or CI.

## Automated verification

```sh
./scripts/verify-ios.sh
```

Requirements: Apple Silicon Mac, Xcode 26.2+ with its Metal toolchain and an installed iPhone
simulator. CI uses macOS 26 and Xcode 26.2. Dependency versions come from the committed
`Package.resolved`. Neither simulator tests nor the Release archive need the large model assets.

The script selects an available iPhone simulator, runs the regular regression suite with model
loading disabled, and archives for a generic physical iOS device. Live website/audio tests
remain opt-in through the separate `Pagehum-PlaybackDiagnostics` scheme. Test failures stop
the script; they are never converted into successful builds.

Xcode 27 on the development machine stalled after reporting all tests passed when debug
library injection was enabled. Simulator verification sets `ENABLE_DEBUG_DYLIB=NO`, disables
verbose failure diagnostics, and applies a per-test timeout. The resulting run completed with
`TEST SUCCEEDED`. Normal app Debug builds retain their existing preview behavior.

Optional environment overrides:

- `PAGEHUM_BUILD_DIR`: DerivedData directory.
- `PAGEHUM_VERIFY_OUTPUT`: a new output directory for the result bundle and archive.
- `PAGEHUM_TEST_DESTINATION`: a simulator destination such as `platform=iOS Simulator,id=…`.

By default, outputs are under `.build/ios-verification-results/<timestamp>/`. Open `Tests.xcresult`
in Xcode to inspect failures. GitHub Actions retains the test bundle for 14 days.

`verify-ios-archive.py` checks the actual built bundle: device platform, matching deployment
versions, child extension identifier, matching version/build numbers, audio-only background
mode, privacy manifests, executable presence, and absence of large bundled voice weights.
It accepts unsigned archives for local/CI verification. Distribution signing is a separate gate.

## Local validation — 22 October 2026

The complete `scripts/verify-ios.sh` workflow exited successfully on Xcode 27.0 / iPhone 17
simulator (iOS 27.0): **88 tests passed, 0 failed, 1 opt-in live test skipped**. Both historical
playback-state failures passed. The physical-device Release archive built successfully and
passed every archive packaging check. Plist validation, shell/Python syntax checks, and
`git diff --check` also passed.

Final local artifacts are `.build/iphone-release-final/Tests.xcresult` and
`.build/iphone-release-final/Pagehum.xcarchive`. The archive is unsigned. Existing vendor/Swift
concurrency warnings remain in the audio-cache and dependency builds; this is not a claim of
Swift 6 strict-concurrency readiness. Signed-device and minimum-iOS acceptance remain pending.

## Reliability changes

- A library that cannot be opened now presents a retry screen. It does not substitute an empty
  in-memory library or delete the existing store. The app and reader model have stable SwiftUI
  ownership across scene updates.
- Import, playback progress, listening-time, favorite, completion, and deletion saves expose
  failures. Pending context changes remain available for retry. Marking an article unread also
  resets its saved text offset.
- The share extension uses extension-safe APIs, validates web URLs, confirms saving, and warns
  before replacing an unimported link. Open Pagehum to import. The app checks on foregrounding,
  deduplicates saved URLs, preserves full query strings, and only clears a handoff after saving.
- Model downloads validate existing files before reuse, replace corrupt assets after checksum
  verification, clean up staging files, and respect cancellation before publishing downloads.
- iOS signing uses an app-group-only entitlement file; macOS-specific sandbox and library
  validation entitlements remain confined to the Mac configuration.

## Privacy declarations

The app declares UserDefaults reasons `CA92.1` (local preferences) and `1C8F.1` (shared link
handoff), plus `C617.1` for metadata of its cached files. The extension declares `1C8F.1`.
These match [Apple’s required-reason API documentation](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
The current manifests declare no tracking or collected data. Review the aggregated archive
privacy report, including dependencies, before each submission; manifests do not replace
App Store Connect privacy disclosures or a published privacy policy.

The extension no longer traverses the responder chain to open the containing app. It uses
shared app-group storage, consistent with [Apple’s app-extension model](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html).

## TestFlight gates

1. Confirm the App Store Connect app record, production bundle identifiers, developer team,
   and app group. Existing checked-in identifiers and the shared group are preserved so current
   installations retain their data. Both targets must use a group authorized for the signing team.
2. Increment `CURRENT_PROJECT_VERSION` in both app and extension for each upload; keep their
   `MARKETING_VERSION` values identical. Archive the `Pagehum-iOS` scheme with distribution
   signing, then validate through Xcode Organizer before uploading.
3. On a physical iPhone, use a fresh Release installation: verify system voices before download,
   download natural voices, interrupt/retry the download, then synthesize offline. The simulator
   cannot validate Kokoro GPU inference, memory pressure, or device background execution.
4. Listen with the screen locked, background/foreground repeatedly, pause/resume from the lock
   screen, unplug headphones, handle an incoming call, change voices/speed, and seek. Test a
   fully cached article and an uncached article; unavailable background GPU work must pause
   cleanly. Record any jetsam, watchdog, or Metal-background failures.
5. Share from Safari while Pagehum is closed and while it is already running. Confirm saving,
   import on return, URL query preservation, no duplicate article, retry after offline failure,
   and the warning when another link is waiting.
6. Upgrade an installation with an existing library. Verify favorite/completion state, resume
   offsets, listening totals, and saved offline audio survive relaunch. Exercise storage failure
   and the retry UI without deleting the user's library.
7. Check the oldest supported iOS version and a current release, Dynamic Type/VoiceOver,
   and iPad layout (the target still supports iPad). Supply screenshots, support/privacy URLs,
   age rating, review notes, and the aggregated privacy report before submission.

This pass does not establish physical-device acceptance, distribution provisioning, App Store
approval, or execution of the newly added workflow on GitHub. Those remain release gates.
