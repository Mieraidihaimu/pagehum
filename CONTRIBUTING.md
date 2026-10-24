# Contributing to Pagehum

Build instructions and requirements are in [README.md](README.md). Run `./scripts/download-models.sh` before building. Keep downloaded weights, build output, personal Xcode state, and signing credentials out of commits.

## Changes

Open an issue for large changes so we can discuss scope. For fixes, include the trigger, the resulting behavior, and how you verified it. Preserve the local speech-generation path and third-party attribution.

Useful areas for contribution include reader extraction, accessibility, playback reliability, language support, and distribution packaging.

## Verification

For the iPhone release, run `./scripts/verify-ios.sh`. It runs simulator tests and verifies an
unsigned Release archive, using the pinned dependency lockfile. It needs Xcode 26.2+ with an
installed iPhone simulator and Metal toolchain. It does not need downloaded voice models.
See [the iPhone release runbook](docs/IOS_RELEASE.md) for artifacts, overrides, and device checks.


Run the Mac tests (local ad-hoc signing omits development-only entitlements). The launch machine currently stalls before executing the app tests; see [release notes](docs/RELEASE_NOTES.md) for that limitation:

```sh
xcodebuild -project Pagehum.xcodeproj -scheme Pagehum-macOS \
  -destination 'platform=macOS,arch=arm64' test \
  CODE_SIGN_IDENTITY=- CODE_SIGN_ENTITLEMENTS= DEVELOPMENT_TEAM=
```

The test scheme sets `KOKORO_SKIP_MODEL_LOADING=1` for tests that do not need real synthesis. CLI verification exercises real synthesis and requires GPU and WebKit access in a logged-in Mac session:

```sh
./scripts/build-cli.sh
python3 scripts/test-cli.py .build/pagehum-cli/pagehum
```

For an opt-in iPhone simulator run using real blog articles and audio playback, see [playback diagnostics](docs/PLAYBACK_DIAGNOSTICS.md). It also records the October 2026 phone crash findings and the limits of simulator coverage.

For changes to resource lookup or packaging, move the full CLI directory to another location and verify synthesis there. Unit tests alone do not validate Metal resource loading.

The two historical playback-state failures, `transitionsFromPreparingThroughAudiblePausedAndFinished` and `allGenerationFailuresRemainIncompleteAndReportEverySentence`, pass in the October 2026 iPhone simulator run. See [iPhone release preparation](docs/IOS_RELEASE.md) for current coverage and remaining device gates; [CLI notes](docs/CLI.md) and the 0.1.0 release notes retain historical results.

## Compatibility

Pagehum keeps the previous bundle identifiers, shared app group, persistent storage keys, and `speechly://` URL compatibility to preserve existing development installations. For a separately signed device installation, configure a matching app group in the app, share extension, and Swift code, together with your own bundle identifiers.
