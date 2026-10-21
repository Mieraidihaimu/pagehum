# Project guidance

This is the Pagehum Xcode project. See README.md and CONTRIBUTING.md for build, setup, and test commands. Shared schemes: Pagehum-macOS, Pagehum-iOS, and pagehum. Run scripts/download-models.sh before building. MLX needs a physical device or an Apple Silicon Mac, not the iOS Simulator.

## Architecture

### Single Model, Multiple Views

`ReaderModel` (`ReaderModel.swift`) is a singleton `@MainActor ObservableObject` instantiated once in `Pagehum.swift` and passed as `@ObservedObject` to every view. It owns the entire TTS pipeline, audio engine, playback state, and content loading.

### Content Flow

```
URL / PDF / pasted text
    ↓
TextExtractor.extract()          → ReadingContent { title, body, source, byline, siteName }
    ↓
ReaderModel.prepareText()       → sentences: [String]  (NLTokenizer + splitLongSentence)
    ↓
startPipeline()  ──@MainActor──  generateSentenceAudio() dispatches to GCD → audioCache[i]
playLoop()       ──@MainActor──  consumes audioCache, schedules AVAudioPlayerNode buffers
updateWordHighlight() ──timer──  maps elapsed wall-clock × speed → currentTokenIndex
```

### Content Source Routing

`ContentSource` (in `ReadingContent.swift`) has three cases: `.url(URL)`, `.pdf(URL)`, `.text(String)`.

- **URL sources** → `WebReaderView` (shows live WKWebView + TTS controls overlay)
- **PDF / text sources** → `ReaderView` (sentence-by-sentence LazyVStack reader)

Routing happens in `HomeView.navigationDestination` and `PlaylistView.navigationDestination` via `content?.source.webURL`.

### TTS Pipeline Details

- **Engine**: Kokoro 82M model via the `KokoroSwift` SPM package. Audio is 24 kHz mono PCM.
- **Model loading**: Happens asynchronously in `loadModel()` on a GCD background queue (not Swift concurrency — MLX uses internal `DispatchQueue.sync` that deadlocks on the cooperative thread pool). `isModelLoaded` gates playback.
- **Audio generation**: `KokoroSpeechEngine` runs model loading, inference, and GPU cleanup on one serial `SpeechSynthesisWorkQueue` via continuations. Never use `Task.detached` for MLX/Kokoro work or access the MLX stream concurrently.
- **Speed**: Applied via `AVAudioUnitTimePitch.rate` (not at generation time — generation always uses `speed: 1.0`). When speed changes mid-playback, `bufferStartTime` is recalibrated to keep word highlight in sync.
- **Lookahead**: 3 sentences pre-generated into `audioCache: [Int: SentenceAudio]`. The generation task stays 3 sentences ahead of the playback cursor.
- **Sentence length limit**: `splitIntoSentences` enforces a 400-character max. Longer sentences are split at clause boundaries (`,;:—–`) or word boundaries to avoid Kokoro's `tooManyTokens` error.
- **Skipped sentences**: If generation fails (returns nil), the sentence index is added to `skippedSentences` and playback advances past it instead of stopping.
- **Word highlighting**: `MToken` objects from Kokoro carry `start_ts`/`end_ts` timestamps. A repeating `Timer` (40ms) computes `elapsed = Date().timeIntervalSince(bufferStartTime) * speed` and finds the current token by timestamp.
- **Playback task tracking**: Both `generationTask` and `playbackTask` must be cancelled (and nilled) before starting new ones. `stop()` handles this. Every `Task { await playLoop() }` assignment goes into `playbackTask`.

### Background Audio

The app is configured for background audio playback (`UIBackgroundModes = audio`). `AVAudioSession` is set to `.playback` / `.spokenAudio` with `policy: .longFormAudio`. Lock screen controls use `MPRemoteCommandCenter` and `MPNowPlayingInfoCenter`.

To guarantee uninterrupted playback and prevent OS termination when backgrounded:
- **Never Call Metal in Background**: Submitting Metal command buffers while backgrounded triggers an immediate process kill (`kIOGPUCommandBufferCallbackErrorBackgroundExecutionNotPermitted` / `SIGABRT`) from the iOS kernel. `ReaderModel` tracks background transitions (`willResignActive`, `didEnterBackground`), halting GPU inference. If an uncached sentence is reached in background, the pipeline pauses cleanly until foregrounded without skipping sentences or corrupting playback.
- **Synchronous Drain Barrier & Jetsam Eviction**: Inside the main-queue `UIApplication.willResignActiveNotification` callback, `KokoroSpeechEngine.drainAndEvictGPU()` suspends its serial work queue, waits for current inference to finish, synchronizes the GPU, and clears its cache. Do not defer this barrier to a Task or run cleanup concurrently with inference. New GPU work is rejected until `didBecomeActive` resumes the queue; system-voice sessions never initialize GPU cleanup.
- **Deep Foreground Pre-caching**: `lookaheadCount = 100` pre-synthesizes sentences into `AudioDiskCache` ahead of playback while in the foreground. Because Kokoro synthesizes at 40x real-time (150ms per sentence), the entire article is cached on disk within seconds of pressing play. Cached `.m4a` files are decoded purely via CPU (`AVAudioFile`) and require zero GPU.
- **Disk Cache Fast-Path**: `SentenceAudioProvider.audioState(at:)` checks `AudioDiskCache` directly, providing instantaneous ready buffers during playback and seeking.
- **Audio Session & Lifecycle**: Uses standard `UIBackgroundModes = audio`, `policy: .longFormAudio`, and listens for `.AVAudioEngineConfigurationChange` to recover the engine during hardware routing or lock-screen transitions.
- **Inaudible Comfort Dither Keep-Alive**: `makeSilenceBuffer` renders imperceptible alternating dither (~ -90 dBFS, `±1.0e-5`) rather than digital zeros. This ensures iOS `mediaserverd` continuously sees non-zero audio frame activity, preventing the system from classifying the session as an idle/silent keep-alive.
- **Guarded Gapless Bridging**: `GaplessSentenceScheduler` maintains continuous buffer playback using silence bridges between sentences, strictly guarded so silence is never scheduled prior to the first sentence buffer being ready.

### Share Extension

`PagehumShare` is a Share Extension target. When a user shares a URL from Safari, the extension:
1. Writes the URL to `UserDefaults(suiteName: "group.com.test.mier.hello")` under key `"SharedURL"`
2. Opens the app via the `pagehum://open?url=` deep link scheme
3. The main app reads the shared URL in `checkForSharedURL()` / `loadPendingSharedURL()`

The app group ID `group.com.test.mier.hello` must match in both targets' entitlements.

### Persistence

`PlaylistItem` is a SwiftData `@Model` stored via `ModelContainer`. It holds the full extracted text (`fullText`) and `lastSentenceIndex` for resume. `ReaderModel.saveProgressNow()` is called after each sentence during playback. The `modelContext` is injected from `Pagehum.swift` after init.

### Offline Audio Cache

`AudioCacheManager` (`Services/AudioCacheManager.swift`) manages `Documents/AudioCache/` for future pre-generated M4A files. The directory is created lazily. Settings screen shows cache size and exposes a clear action.

## Key Invariants

- **Never use `Task.detached` for MLX/Kokoro work** — MLX uses `DispatchQueue.sync` internally which deadlocks on Swift concurrency's cooperative thread pool. Use the dedicated serial `SpeechSynthesisWorkQueue` for loading, inference, and GPU cleanup.
- **Never stop `audioEngine`** during normal operation — only stop `playerNode`. The engine stays alive for the model's lifetime.
- **Views must NOT call `cleanup()` / `stop()` on disappear** — `ReaderModel` is a singleton that persists across navigation. Stopping playback on view disappear breaks background audio and re-entry. Only the user or explicit actions (loading new content) should stop playback.
- **`audioCache` and `skippedSentences` are @MainActor** — access only from the main actor. Always clear both together: `audioCache = [:]; skippedSentences = []`.
- **Pipeline loops must yield** — The generation loop in `startPipeline` runs on `@MainActor`. Add `await Task.yield()` in tight loops (e.g., cache-hit iteration) to avoid starving the UI, especially WKWebView.
- **JS injection in WebReaderView** always uses `JSONSerialization` to encode sentence strings before passing to JavaScript — never manual string interpolation.
- **WebViewContainer must be lightweight** — only pass the current sentence string, not the full `sentences` array. Passing large arrays causes expensive SwiftUI diffing on every `@Published` change.
- **Bundle IDs**: The main app uses `com.test.mier.hello` (iphoneos) and the Share Extension must use a child bundle ID of the same prefix.

## File Map

| File | Role |
|------|------|
| `Pagehum.swift` | App entry point, ModelContainer setup, deep link handling |
| `ReaderModel.swift` | Singleton model: TTS pipeline, audio engine, playback state, content loading |
| `Models/ReadingContent.swift` | `ContentSource` enum + `ReadingContent` struct |
| `Models/PlaylistItem.swift` | SwiftData `@Model` for saved articles |
| `Views/HomeView.swift` | URL/file/text input screen |
| `Views/ReaderView.swift` | LazyVStack sentence reader with word highlighting |
| `Views/WebReaderView.swift` | WKWebView reader with sentence highlighting overlay |
| `Views/PlaylistView.swift` | Library of saved/in-progress/completed articles |
| `Views/PlaybackControlsView.swift` | Expandable/minimizable transport controls |
| `Views/SettingsView.swift` | Speed, text size, voice picker, cache management |
| `Services/TextExtractor.swift` | URL (Readability-style JS), PDF, plain text extraction |
| `Services/AudioCacheManager.swift` | On-disk M4A cache directory management |
| `PagehumShare/ShareViewController.swift` | Share Extension for receiving URLs from other apps |
