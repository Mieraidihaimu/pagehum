# Pagehum — Recovered Design

## 1. One-paragraph summary

Pagehum (product name "Pagehum") is an on-device neural text-to-speech reader for iOS/macOS that turns web articles, PDFs, and pasted/shared text into spoken audio, fully offline after model load. It runs the Kokoro 82M TTS model via Apple MLX (`KokoroSwift` + `MisakiSwift` G2P + `MLXUtilsLibrary`), extracts readable text with a hand-rolled Readability-style JS scorer in a headless `WKWebView` (plus PDFKit), and plays sentence-by-sentence with word-level highlighting, background/lock-screen controls, a SwiftData library with resume, and a disk cache that lets re-reads skip inference. A single `@MainActor` god-object, `ReaderModel`, orchestrates everything.

## 2. The naive model vs. reality

**User's mental model:** import model + library → extract text → hand a string to the audio engine → play.

What the code actually adds on top, and why:

| Addition | Why it exists |
|---|---|
| MLX work forced onto GCD (`withCheckedContinuation` + `DispatchQueue.global`), never `Task.detached` | MLX uses `DispatchQueue.sync` internally, which **deadlocks** Swift concurrency's cooperative pool (CLAUDE invariant). |
| Sentence segmentation with a 400-char cap + clause/word-boundary splitting (`splitIntoSentences`/`splitLongSentence`) | Kokoro has a **510-token limit** (`tooManyTokens`); over-long sentences must be split or **skipped** (dropped content). |
| A full neural G2P→PLBERT→duration→prosody→text-encoder→iSTFTNet pipeline inside `generateAudio` | "Text → audio" is really a multi-stage ML pipeline, not one call; it also emits per-token timestamps. |
| Look-ahead producer/consumer pipeline (`generationTask` fills `audioCache`, `GaplessSentenceScheduler` consumes) decoupled by `lookaheadCount=3` | Playback must start before all audio exists; `skippedSentences` lets playback advance past failed sentences. |
| `GaplessSentenceScheduler` keeping ≥2 buffers in-flight | The old `playLoop` awaited each buffer completion on a main-actor round-trip, causing an **audible gap**. |
| Wall-clock word-highlight timer (`elapsed × speed` vs `WordTiming.start`) with `bufferStartTime` recalibration | Highlighting is derived from the clock, not an audio tap, so it must be nudged on speed change, pause, seek, and AAC priming. |
| Disk cache (`AudioDiskCache`) = AAC `.m4a` + JSON sidecar, SHA256-keyed, "every failure → nil → regenerate" | Avoid re-running Kokoro on re-read/seek/offline; a prior attempt **crashed**, so crash-avoidance dominates the design. |
| `WordTiming` DTO replacing `MToken` | `MToken` is MLX-bound and not `Codable`; the cache/scheduler must stay MLX-free and off-device-testable. |
| Speed applied post-generation via `AVAudioUnitTimePitch.rate` (generation always `speed:1.0`) | One cache entry serves all speeds; but forces manual clock recalibration. |
| Share Extension bridged via app-group `UserDefaults` + `pagehum://` deep link | The extension is a separate process; no shared object references. |

## 3. Requirements (recovered)

**Functional**
1. [explicit] Convert web URL, local PDF, and pasted text into speech, fully on-device after model load.
2. [explicit] Run Kokoro 82M via MLX producing 24 kHz mono Float32 PCM, faster than real time.
3. [explicit] Extract article text via Readability-style JS in a headless `WKWebView`; PDF via PDFKit; text passthrough.
4. [explicit] Sentence-by-sentence playback with 3-sentence look-ahead, 0.75×–3× speed, word-level highlighting.
5. [explicit] Background audio + lock-screen/Control-Center transport (`MPRemoteCommandCenter`/`MPNowPlayingInfoCenter`).
6. [explicit] SwiftData library (queued/in-progress/completed) with resume from `lastSentenceIndex`.
7. [explicit] 28 bundled voices, selectable and changeable mid-playback.
8. [explicit] Safari Share Extension (`PagehumShare`, `com.test.mier.hello.PagehumShare`) handing URLs via app group + deep link.
9. [explicit] Settings expose audio-cache size/count/clear.
10. [explicit, planned] A1 disk cache (implemented in code per readers) and A2 gapless playback (in progress).
11. [inferred] Per-day listening-time stats (`ListeningRecord`, `StatsView`) — present in code, not emphasized in top-level docs.

**Non-functional**
1. [explicit] Physical device only; no iOS Simulator (MLX has no Simulator slice).
2. [explicit] MLX bounded: `GPU.set(cacheLimit:512MB)`, `memoryLimit:2048MB`; ~2 GB MLX ceiling.
3. [explicit] Never `audioEngine.stop()` during normal operation (only `playerNode.stop()`); engine lives for model's lifetime.
4. [explicit] Views must not `stop()`/`cleanup()` on disappear (singleton persists across navigation).
5. [explicit] All MLX work off the cooperative pool via GCD; pipeline loops `Task.yield()` to avoid starving UI/WKWebView.
6. [explicit] Disk cache is a pure optimization — degrade to cache-miss, never crash.
7. [inferred] No test target exists; A1/A2 ship with unit-test specs (12 and 13 cases) contingent on adding a test bundle.

## 4. Scope / non-scope

**In scope:** offline TTS of URL/PDF/text; look-ahead generation + gapless playback; word/sentence highlighting; 28 voices; speed/pitch-preserved rate; background + remote controls; SwiftData library with resume; per-day listening stats; disk audio cache; Safari share-in.

**Deliberately out of scope / not built:**
- Pre-generated **full-article** M4A + sentence-timestamp sidecar for resume-with-seek (SPEC "What's Not Yet Built" / Specs "Future").
- Streaming generation, per-sentence multi-language auto-detection, sleep timer, auto-play on resume, "Continue listening" Home card.
- Share intake of **arbitrary prose** — plain text is accepted only if it `hasPrefix("http")`; otherwise dropped, despite an internal `.text` source.
- Unit tests / CI (no test target; device-only build blocks off-device CI).
- Any network for synthesis.

## 5. Entities

Canonical, deduplicated:

| Name | Kind | Key fields | Persisted? where |
|---|---|---|---|
| `ReaderModel` | `@MainActor` `ObservableObject` singleton | ~13 `@Published` (content, sentences, currentSentenceIndex, currentWordText, currentTokenIndex, progress, isPlaying/isPaused/isGenerating/isLoading, speed, selectedVoice, textSize, errorMessage) + engine/scheduler/cache handles | No (in-memory); owns injected `modelContext` |
| `ContentSource` | enum | `.url(URL)`/`.pdf(URL)`/`.text(String)`; computed `webURL` (routing) | No (transient) |
| `ReadingContent` | struct | title, body, source, byline?, siteName? | No (transient) |
| `PlaylistItem` | SwiftData `@Model` | title, sourceURL?, sourceType, textPreview, fullText, dateAdded, lastPlayed, progressPercent, lastSentenceIndex, status (raw `String`) | Yes — SwiftData `ModelContainer` |
| `ListeningRecord` | SwiftData `@Model` | dateString `@Attribute(.unique)`, date (startOfDay), secondsListened | Yes — SwiftData |
| `WordTiming` | struct (`Codable`, `Equatable`) | text, start?, end? (sec @1.0×) | Yes — JSON sidecar in disk cache |
| `SentenceAudio` | struct | buffer (`AVAudioPCMBuffer`), tokens (`[WordTiming]?`), leadingSilence | No (in-memory `audioCache` + returned by cache) |
| `MToken` | class (`MLXUtilsLibrary`) | text, phonemes, POS, start_ts/end_ts | No — mapped to `WordTiming` at generation boundary |
| `SentenceAudioState` | enum | `.ready(SentenceAudio)`/`.pending`/`.skipped` | No |
| `GaplessSentenceScheduler` | `final class` `@MainActor` | nextToSchedule, inFlight, audioByIndex, announcedHead, isActive | No |
| `AudioBufferPlayer` / `AVAudioPlayerNodeAdapter` | protocol + impl | wraps `AVAudioPlayerNode` | No |
| `SentenceAudioProvider` | protocol (impl by `ReaderModel`) | sentenceCount, audioState(at:) | No |
| `AudioDiskCache` | `final class` (`.shared`) | maxBytes=500MB, serial queue, schemaVersion=1, modelTag=`kokoro-v1_0`, aacPrimingFrames=2112 | manages files on disk |
| `AudioCacheManager` | enum (statics) | cacheDirectory (Documents/AudioCache/, excluded-from-backup) | manages dir |
| `TextExtractor` | `@MainActor final class` | transient `WKWebView`, static `readerJS` | No |
| `ShareViewController` | `UIViewController` (extension) | appGroupID `group.com.test.mier.hello`, key `SharedURL` | writes app-group `UserDefaults` |
| `Color` (extension) | SwiftUI utility | platform system-color aliases | No |

## 6. Architecture at a glance

`ReaderModel` is the orchestrator; nearly every subsystem hangs off it. Views observe it; libraries are called from it.

```
                 ┌──────────────── SwiftUI Views ────────────────┐
   HomeView   ReaderView / WebReaderView   PlaybackControlsView
   SettingsView   PlaylistView(@Query)   StatsView(@Query)
                 └───────────────────┬───────────────────────────┘
                        @ObservedObject (all views)
                                     │
        ┌──────────────────── ReaderModel (@MainActor god-object) ─────────────────┐
        │  content ingest · sentence split · look-ahead gen · playback state ·       │
        │  word-highlight clock · progress + listening persistence · remote/session  │
        └──┬───────────┬───────────┬───────────┬───────────┬───────────┬────────────┘
           │           │           │           │           │           │
      TextExtractor  KokoroTTS   AudioDiskCache  Gapless-   AVAudioEngine  SwiftData
      (WKWebView/    (KokoroSwift  (.m4a+JSON,    Sentence-  graph:         ModelContext
       PDFKit/       + MisakiSwift SHA256,        Scheduler  player→time-   (PlaylistItem,
       NLTokenizer)   G2P + MLX +  LRU 500MB)     + Audio-   Pitch→mixer    ListeningRecord)
                      MLXUtils/                    BufferPlayer
                      npz voices)                  (AVAudioPlayerNode)
           │
   Share Extension (separate process) ──app-group UserDefaults + pagehum://──▶ App entry
```

Signal chain: `AVAudioPlayerNode → AVAudioUnitTimePitch(rate=speed) → mainMixerNode → output`, all at 24 kHz mono; engine never torn down.

## 7. Data flow — WRITE path (text → cached audio)

1. **Intake.** URL/PDF/text from `HomeView`, a `PlaylistItem`, or a shared item. `load(from: ContentSource)` sets `isLoading`, calls `stop()`.
2. **Extraction** (`TextExtractor.extract`): 
   - Web — transient headless `WKWebView`, load raced against 20 s timeout (`NavDelegate` → `CheckedContinuation`) + 500 ms settle, then `readerJS` (clone DOM, strip unlikely nodes, score by text/comma/link-density, prefer `<article>`); throws `zeroByteResource` if empty.
   - PDF — `Task.detached` PDFKit page iteration (off main; note: this `Task.detached` is allowed — the ban is MLX-specific).
   - Text — passthrough.
   Result → `ReadingContent`; `content` set; `saveToPlaylist` inserts `PlaylistItem(fullText)`.
3. **Segmentation** (`prepareText → splitIntoSentences`): `NLTokenizer(.sentence)`; ≤400 chars kept, else `splitLongSentence` (clause delimiters `,;:—–` at ≥80 chars, else word packing). Resets index/progress, clears `audioCache`+`skippedSentences`.
4. **Look-ahead loop** (`startPipeline`, `generationTask`, `@MainActor` Task): iterate `genIndex` staying ≤`lookaheadCount(3)` ahead of the playback cursor; `Task.yield()`/`sleep 200ms` to throttle and not starve UI.
5. **Per-sentence generate** (`generateSentenceAudio`, **on `DispatchQueue.global(.userInitiated)` via `withCheckedContinuation` — never `Task.detached`**):
   - **Cache lookup first:** `AudioDiskCache.load(text,voiceKey)` (`voiceKey = selectedVoice + ".npy"`; speed excluded from key). Hit → return `SentenceAudio` immediately (**skip Kokoro**).
   - Miss → `engine.generateAudio(voice:language:text:speed:1.0)`: Misaki G2P → phoneme tokenize (≤510) → PLBERT → BiLSTM duration → prosody F0/N → text encoder → iSTFTNet decoder → `[Float]`@24kHz + `[MToken]` (timestamped by `TimestampPredictor`). Language = `selectedVoice.first == 'a' ? .enUS : .enGB`.
6. **PCM assembly:** allocate `AVAudioPCMBuffer` (24 kHz mono Float32), `copyMemory` samples into channel 0; map `MToken → WordTiming`; wrap in `SentenceAudio`.
7. **Cache write (fire-and-forget):** `AudioDiskCache.store` on serial queue `com.pagehum.audiodiskcache`: write `.m4a.tmp` (AAC-LC 32 kbps) + `.json.tmp` (`.atomic`), rename `.m4a` then `.json` **last (commit marker)**, then `enforceBudget()` (mtime-LRU to 500 MB). Playback never blocks on this.
8. **Publish:** insert into `audioCache[genIndex]` (or `skippedSentences` on failure), clear `isGenerating`, call `scheduler.notifyAvailable()`.

## 8. Data flow — READ/PLAYBACK path (queued audio → speakers)

1. **Start** (`play()` fresh-start): ensure `AVAudioSession` active + `audioEngine` running (engine started **before** scheduler); `startPipeline()`; `scheduler.start(from: currentSentenceIndex)`.
2. **Refill** (`GaplessSentenceScheduler.refill`): read `provider.audioState(at:)` — `.ready` → `player.schedule(buffer, .dataPlayedBack)` until `inFlight.count == maxInFlight`; `.skipped` → advance cursor silently; `.pending` → **stall** (return) until `notifyAvailable()` fires. **Cache-hit shortcut:** the audio may have come from `AudioDiskCache` in step 5 above, so no MLX inference ran at all.
3. **Audible head** (`syncAudibleHead`): fires `onSentenceStarted(index, audio)` once per head → `handleSentenceStarted`: set `currentSentenceIndex`/`currentTokens`, `bufferStartTime = now + audio.leadingSilence` (AAC priming compensation), `progress = index/count`, evict `audioCache` entries `< index`, start word timer, `saveProgressNow()`.
4. **Gapless advance:** `AVAudioPlayerNode` fires `.dataPlayedBack` on its internal queue → `AVAudioPlayerNodeAdapter` hops to `DispatchQueue.main` → `MainActor.assumeIsolated` → `handleCompletion`: guard `isActive`, `removeFirst` (fallback `removeAll{==index}`), `refill()`, `syncAudibleHead()`. Successor was already scheduled → no gap.
5. **Word highlight** (40 ms `Timer` → `Task{@MainActor}`): `elapsed = (now - bufferStartTime) * speed`; last token with `start <= elapsed` → publish `currentTokenIndex`/`currentWordText`. (Note doc drift: SPEC says 25 Hz, CLAUDE/code say 40 ms.)
6. **UI:** `ReaderView`/`SentenceView` re-derive the display word via `findActiveWordIndex` (±2 positional window + fallback) since tokens ≠ display words 1:1; `WebReaderView` fuzzy-matches first 60 chars in a live DOM to tint the sentence.
7. **Stats/persistence:** `ListeningRecord` upserted per day (accumulator flushed every 30 s and on pause/stop, scaled by speed); `PlaylistItem` progress/status updated via `saveProgressNow`.
8. **Finish** (`onFinished → handlePlaybackFinished`): `progress=1.0`, timers stopped, listening/progress saved (item → completed), idle timer re-enabled.

## 9. Key workflows

- **Play (fresh)** — user taps play → guard `sentences` non-empty + `isModelLoaded` → cancel `generationTask`/`scheduler.stop()`, activate session/engine, clear caches, `startPipeline()` + `scheduler.start`, disable idle timer, `updateNowPlayingInfo`.
- **Pause / resume** — pause: capture `pauseElapsed = now - bufferStartTime`, `scheduler.pause()`, stop word timer, save listening + progress. Resume: `scheduler.resume()`, `bufferStartTime = now - pauseElapsed`, restart word timer. Buffers retained (no re-schedule).
- **Skip / seek** — `skipForward/Backward` convert 20 s × ~13 chars/s into a target index; `seekToSentence` tears down scheduler + `generationTask` + timers, **clears `audioCache`/`skippedSentences` (forces regeneration)**, sets index, saves; if was playing, restarts pipeline + scheduler.
- **Add to playlist** — every load auto-inserts a `PlaylistItem` (fullText); `saveForLater` inserts a queued item; swipe-to-delete in `PlaylistView`.
- **Change voice** — `selectedVoice` didSet persists to UserDefaults; if playing, cancels `generationTask`, clears caches, restarts pipeline with new `voiceKey` + inferred language.
- **Change speed** — set from `SettingsView` chips or `PlaybackControlsView` cycle → `speed` didSet sets `timePitch.rate`, recalibrates `bufferStartTime` (folds `elapsed × oldSpeed` into listening accumulator), persists.
- **Share-to-app** — Safari share → `ShareViewController` writes `SharedURL` to app group **and** opens `pagehum://open?url=` (via responder-chain `openURL:` trick) → app consumes via `onOpenURL`→`handleOpenURL` **and/or** `onAppear`→`checkForSharedURL` → `pendingSharedURL` → `loadPendingSharedURL` → `loadURL`.
- **View stats** — `StatsView` reads `ListeningRecord` `@Query` directly; fully decoupled from `ReaderModel`.

## 10. Where the complexity actually lives

Ranked by contribution to "it feels complex now":

1. **`ReaderModel.swift` (~903 loc) — the god-object.** Facts confirm it: one `@MainActor` class fusing ~8 subsystems (audio graph, model lifecycle, ingest, NL splitting, look-ahead pipeline, playback state machine, word timing, two SwiftData persistence flavors) + platform glue, ~13 `@Published` + ~20 private fields; invariants (clear `audioCache`+`skippedSentences` together; cancel+nil `generationTask`) enforced only by convention. **Candidate seams:** (a) a `ContentIngest`/segmentation service, (b) a `GenerationPipeline` producer, (c) a `PlaybackController` around the scheduler, (d) a `WordHighlightClock`, (e) `ProgressStore` + `ListeningStore`. The scheduler/provider/player split (A2) already models the right pattern.
2. **Gapless playback + word-timing sync.** Two independent notions of position (event-driven audible cursor vs wall-clock highlight clock) kept in sync across pause/speed/seek/AAC leading-silence; completion ordering assumed but defensively handled; ≥2 in-flight required.
3. **TTS/ML synthesis pipeline.** Multi-stage neural graph + two artifact formats (safetensors via MLX, `voices.npz` via ZIP), voice embedding split by phoneme-token length, MLX/GCD deadlock avoidance threaded throughout.
4. **`AudioDiskCache` (A1).** Two-file atomic-by-ordering commit, lossy AAC 2112-frame priming compensation, multi-gated validity, LRU across paired files — dominated by crash-avoidance.
5. **Web extraction.** Hand-rolled ~160-line Readability JS in a full headless render (20 s race + 500 ms settle), rendered twice (extract vs live highlight), fuzzy 60-char DOM match.
6. **App lifecycle / share bridge.** Manual DI (`let model`, not `@StateObject`), two-phase container wiring, dual/racy share handoff, per-SDK bundle IDs, `try!` container.
7. **Views layer.** Mostly thin, but `findActiveWordIndex` lossy mapping, polymorphic reader routing, and Settings writes with live pipeline side effects add hidden coupling.

## 11. Risks / smells / open questions

1. **Doc/code drift — do not trust docs as ground truth.** CLAUDE.md still describes `playLoop()`/`playbackTask`, but code moved to `GaplessSentenceScheduler` + `generationTask`. Highlight timer rate disagrees (25 Hz SPEC vs 40 ms CLAUDE/code). SPEC says generation uses `Task.detached`; CLAUDE forbids it — **CLAUDE invariant (GCD only) is authoritative.** Platform version drift: README iOS 18.0+/macOS 15.0+ vs SPEC/Specs/CLAUDE iOS 18.6+.
2. **A1/A2 status ambiguity.** Top-level docs call A1/A2 "planned/in progress," but the code readers describe `AudioDiskCache.swift`, `GaplessSentenceScheduler.swift`, `AudioBufferPlayer.swift`, and `WordTiming.swift` as present and integrated. Verify what actually ships vs what's stubbed before refactoring around them.
3. **Concurrency hazards.** MLX must never run on the cooperative pool (`Task.detached`) — a wrong dispatch silently deadlocks. Completion-order assumption (`removeFirst`) relies on `.dataPlayedBack` ordering + main-thread hop. `init()` references `self` as scheduler provider before setup completes (documented ordering constraint). `TextExtractor` stores its `WKWebView` on `self` and nils it — **concurrent extractions clobber each other.**
4. **Cache-invalidation correctness.** Key = `SHA256(schemaVersion|modelTag|voiceKey|text)`, **speed excluded** (intentional). Bumping `schemaVersion`/`modelTag` invalidates all. AAC priming compensation (trim vs `leadingSilence`) is a real correctness nuance — highlight can run ahead on a hit if mis-handled. mtime bumped only on `.m4a` during `load()`; eviction removes `.m4a`+`.json` pairs — verify sidecar orphans can't accumulate.
5. **Content-loss tradeoffs.** Sentences that stay >400 chars after splitting are **skipped** (dropped audio). Share intake drops non-`http` prose despite an internal `.text` source.
6. **State-model footguns.** `PlaylistItem.status` stored as raw `String` with a shadow `Status` enum — model and persisted value can drift. `WordTiming`/`ReadingContent`/`ContentSource` are not `Identifiable` (ForEach needs explicit ids).
7. **Missing tests / device-only.** No test target; A1/A2 unit-test specs (12 + 13 cases) require someone to add a `PagehumTests` bundle. Whole app is unbuildable/untestable off a physical device (no MLX Simulator slice) — hard CI story.
8. **Fragile platform tricks.** Extension opens host app via `perform(NSSelectorFromString("openURL:"))` (semi-private). `disable-library-validation` entitlement required for embedded MLX/Kokoro frameworks. App-group share flow only lines up on iOS bundle IDs.
9. **Tight coupling / duplication.** `play`/`seek`/`skip`/`stop` each re-tear-down the same tasks/timers/caches — duplicated teardown that must stay in sync. Speed has multiple UI writers into one `@Published`. Progress is computed two ways in `PlaybackControlsView` (chars/sec estimate vs model `progress`).

*Note on source confidence:* all facts above are from the 9 reader summaries, not a re-read of source. Where readers conflicted (A1/A2 status, timer rate, `Task.detached`), the disagreement is flagged rather than resolved.
