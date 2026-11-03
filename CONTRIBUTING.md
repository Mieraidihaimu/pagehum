# Contributing to Pagehum

Build instructions and requirements are in [README.md](README.md). Run `./scripts/download-models.sh` before app Debug builds or CLI synthesis. The fast maintenance checks and iPhone release verification do not require model downloads. Keep downloaded weights, build output, personal Xcode state, and signing credentials out of commits.

## Changes

Open an issue for large changes so we can discuss scope. For fixes, include the trigger, the resulting behavior, and how you verified it. Preserve the local speech-generation path and third-party attribution.

Useful areas for contribution include reader extraction, accessibility, playback reliability, language support, and distribution packaging.

## Verification

Start every change with the fast, offline checks (Python 3.11+ and Bash):

```sh
python3 scripts/check-maintenance.py
```

This checks shell/Python syntax, parses app and extension plists, privacy manifests,
entitlements, asset catalogs, localization JSON, dependency lockfiles, and shared schemes,
then runs archive-verifier regression tests against small synthetic archives. It works from
any working directory, without Xcode, model downloads, or third-party Python packages.
GitHub Actions runs it on Linux and macOS for every pull request and push to `main`.

Choose the additional checks that exercise the behavior you changed:

| Change | Additional verification |
| --- | --- |
| App, share extension, playback, or persistence | `./scripts/verify-ios.sh`; physical-device checks for GPU/background behavior |
| CLI, model lookup, or bundled resources | Build CLI, run `scripts/test-cli.py`, then verify synthesis from a relocated CLI directory |
| Archive validation rules | Add positive/negative cases in `scripts/tests/test_verify_ios_archive.py`; run `./scripts/verify-ios.sh` against a real archive |
| Workflow or dependency configuration | Review workflow triggers/permissions and check the resulting GitHub Actions runs |

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

## Routine maintenance

Dependabot checks GitHub Actions weekly, grouping minor/patch updates and leaving major
updates separate. Review the release notes and CI results before merging these pull requests.
See [GitHub's configuration reference](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference).

Review Swift dependencies monthly and before releases. Versions are declared in both
`Packages/SpeechCore/Package.swift` and `Pagehum.xcodeproj/project.pbxproj`; the app/CLI share
the lockfile at `Pagehum.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
Update matching version requirements together, resolve packages with Xcode, and commit the
updated lockfile. Swift dependencies remain a manual review because updating only the local
package manifest does not update the app's pinned graph. Verify both the iPhone app and CLI,
including real synthesis, when upgrading Kokoro, MLX, or their dependencies.

When updating model assets, keep the revision and SHA-256 values in
`scripts/download-models.sh` and `Pagehum/Speech/ModelStore.swift` aligned. Test setup and
in-app downloads, and review third-party licenses/notices. When changing the Xcode version or
runner in CI, update the requirements in this guide and `docs/IOS_RELEASE.md` together.
