# Pagehum 0.1.0 — initial public prerelease

Your reading list, read aloud.

## Included

- A native SwiftUI reader for articles, PDFs, and pasted text, with a saved library and listening queue.
- Local Kokoro/MLX speech generation.
- A macOS CLI for text, file, stdin, and article URL input, with M4A and WAV export.
- Unified Pagehum app, Xcode project, targets, CLI, resource bundle, and documentation names.
- A pinned, checksum-verified model download script for source builds.
- A portable Apple Silicon CLI archive with model assets, resource bundles, frameworks, and license notices.

Existing app identifiers, app-group storage, and `speechly://` links are retained for development-installation compatibility. New sharing uses `pagehum://`.

## Downloads

- `pagehum-0.1.0-macOS-arm64.tar.gz`: CLI and required resources, for Apple Silicon and macOS 15.6+.
- `pagehum-0.1.0-macOS-arm64.tar.gz.sha256`: archive checksum.
- `pagehum-sample.m4a`: short original narration generated with the packaged CLI.

The CLI is an unsigned, unnotarized prerelease. Keep the extracted directory together. If macOS blocks it, build from source using the README. No signed GUI application or iOS binary is included.

## Validation on the release machine

- Xcode 27.0 on an Apple Silicon Mac running macOS 26.6.2.
- CLI Release build: passed.
- Fresh model and voice downloads: passed SHA-256 verification against the pinned assets.
- CLI smoke tests: passed for input selection, voices, errors, overwrite protection, real speech generation, WAV, all AAC presets, and local HTML article extraction.
- Extracted archive: generated valid 24 kHz mono AAC while the original Release build directory was temporarily unavailable.
- Mac app and test bundle: build-for-testing passed with ad-hoc signing and development-only entitlements omitted for the test build.
- Full app test execution: blocked on this machine before tests reported results; the test host stalled in the macOS dynamic loader. Unsigned, ad-hoc-signed, and relocated launches were attempted. This is not a passing app-test result.
- Added regression coverage for both `pagehum://` and legacy `speechly://` shared links; it compiles with the app tests, but execution remains subject to the host-launch limitation above.
- iOS device/archive validation has not been performed. The app target is iOS 18.6+, while the bundled share extension currently requires iOS 26.1.

Earlier development notes recorded two playback-state test failures; this release does not claim those issues are resolved. See CONTRIBUTING.md and CLI.md.

## Source history

The public repository starts with a clean source snapshot of this development project, retaining upstream attribution. Large model files and personal Xcode state are excluded. The original development history remains in the local repository; model assets remain on disk and can be downloaded independently for new clones.
