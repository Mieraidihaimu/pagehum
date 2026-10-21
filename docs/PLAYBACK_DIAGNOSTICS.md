# Playback crash investigation — 21 October 2026

Three crash reports from the connected iPhone identified two failure paths:

- At 16:05 and 16:08 BST, `SentenceView.findActiveWordIndex` trapped while constructing a Swift range. Speech token indexes can exceed the number of whitespace-separated words, especially around punctuation. Highlight searches now handle empty sentences and clamp both search bounds. Web articles now display only their original page; PDFs and pasted text retain the text surface with this bounds fix.
- At 10:17 BST, Metal aborted while Kokoro inference created a command encoder on a worker thread and the main thread ran GPU cache cleanup. Model loading, inference, and cleanup now share a serial work queue. The resignation callback synchronously suspends and drains that queue before returning; foreground activation resumes it. A session using only system voices does not initialize GPU cleanup.

Raw phone reports stay outside the repository.

## Automated regressions

`SentenceHighlightTests` exercises empty input, unmatched speech tokens, punctuation, negative indexes, and indexes beyond the displayed words. `SpeechSynthesisWorkQueueTests` verifies that cleanup waits for inference, suspended work is rejected, and foreground resumption allows work again.

## Live blog playback

The opt-in `LiveBlogPlaybackTests` uses real website extraction, speech synthesis, audio playback, and `PhoneReaderView` in a visible test window. It checks spoken-word updates, sentence transitions, pause/resume, speed changes, skips, mid-article seeking, restart, rapid seeks, complete playback, and automatic queue advancement. Its library is in memory, and it restores the saved voice and speed preferences.

The reproduction URLs are:

- <https://unsung.aresluna.org/good-type-against-all-odds/>
- <https://martinfowler.com/bliki/TwoHardThings.html>

Run on an available iPhone simulator, replacing the destination with its identifier:

```sh
xcodebuild -project Pagehum.xcodeproj -scheme Pagehum-PlaybackDiagnostics \
  -destination 'id=SIMULATOR_IDENTIFIER' -derivedDataPath .build/pagehum-app \
  -disableAutomaticPackageResolution -parallel-testing-enabled NO \
  -only-testing:PagehumTests/LiveBlogPlaybackTests \
  CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES test
```

This scheme enables `PAGEHUM_LIVE_BLOG_TESTS=1`; the live test is skipped in normal test runs. Use the explicit test filter above to run it alone. Expect audible playback at up to 3× speed and network access to the two articles.

The simulator uses Apple's system voices. It validates the reading and playback paths but cannot validate Kokoro GPU behavior or physical-device screen-lock handling. Those require a signed iPhone build and a device retest.

## Recorded result

On 21 October 2026, the live scenario passed on the iPhone 17e / iOS 27 simulator in 118 seconds. Both articles played through to completion at 3×, with zero reported skipped sentences. The control checks and automatic queue advance also passed while the app displayed the original web pages.

The final related regression run passed 30 tests across seven suites (highlighting, GPU work ordering, playback state, queue behavior, scheduling, and speech engines). The unsigned generic iPhone build also passed. The patched build has not been installed on the physical phone.
