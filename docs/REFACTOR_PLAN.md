# ReaderModel — Replaceability-Driven Refactor Plan

## 1. Goal & principle

A unit is **replaceable** iff its implementation can be deleted and regenerated correctly from three durable artifacts alone: (1) a written contract spec, (2) a stable Swift protocol its collaborators depend on, and (3) a test suite pinning behavior. The implementation is **disposable**; spec + protocol + tests are **durable**. The hard rule: a unit communicates only through explicit inputs/outputs/events/callbacks — it never reaches into `ReaderModel`'s `@Published` fields, and no two units share a mutable stored property across a seam.

"Done" looks like this: `ReaderModel` shrinks from ~903 lines to a ~120–160-line **composition root** that holds only genuinely-shared `@Published` UI state and wires ~10 protocol-backed units together. Each unit lives behind a protocol, has a `docs/specs/<Unit>.md`, and has a test file green in CI. Any one unit's concrete type can be `rm`'d and re-derived from its spec+protocol+tests without reading the others.

## 2. Target architecture

```
                         ┌───────────────────────────────────────────────┐
                         │  ReaderModel  (@MainActor composition root)   │
                         │  - owns ONLY shared @Published UI state:        │
                         │    isPlaying,isPaused,progress,currentSentence  │
                         │    Index,currentTokenIndex,currentWordText,     │
                         │    content,isLoading,errorMessage,voiceNames,   │
                         │    selectedVoice,isModelLoaded,isGenerating,    │
                         │    savedConfirmation,pendingSharedURL           │
                         │  - constructs units, wires callbacks/events     │
                         │  - thin forwarding methods for Views            │
                         └───────────────────────────────────────────────┘
        ┌──────────────┬───────────────┬──────────┬──────────────┬─────────────┐
        v              v               v          v              v             v
 SentenceSegmenting  ModelLoading   TextIngesting  ProgressStoring  NowPlaying   WordHighlight
 (pure)              +VoiceName-    +TextExtracting +ListeningStoring Controller   Clock
                     Deriver        +SharedURLInbox                  +RemoteCmd-  +DateProvider
                     +VoiceSelection +ContentLoader                  Handler      +HighlightTicker
                          │              │                            (snapshot)
                          │ LoadedModel  │ IngestedDocument
                          v              v
                    ┌─────────────────────────────────────────────────────────┐
                    │            PlaybackControlling  (the spine)              │
                    │  +PlaybackContentSource  +AudioGraphControlling          │
                    │  drives ↓        emits events →  clock / progress /      │
                    │                                  listening / nowplaying  │
                    └─────────────────────────────────────────────────────────┘
                        │ start(from:)/stop()          │ reads/writes via
                        v                               v
              GaplessSentenceScheduler  ───────►  SentenceAudioStore  ◄─── GenerationPipeline
              (EXISTS)                            (audioState/put/evict)      │ writes
                  │ uses                                                      v
                  v                                            SentenceAudioSynthesizer
        AudioBufferPlayer / AVAudioPlayerNodeAdapter (EXISTS)  (MLX boundary, GCD-only)
                                                                    │ uses
                                                                    v
                                                            AudioDiskCache (EXISTS)
```

**Final unit set** (one-line responsibility each):

| Unit (protocol) | Responsibility |
|---|---|
| `SentenceSegmenting` | Pure split of body text into ≤400-char trimmed chunks (`splitIntoSentences`). |
| `WordHighlightClock` | Derive spoken token index/text from a speed-scaled wall-clock anchor over `[WordTiming]`. |
| `ProgressStoring` | SwiftData persistence of per-article resume position + status on `PlaylistItem`. |
| `ListeningStoring` | Per-day `ListeningRecord` accumulation (speed-scaled wall clock, 30s flush). |
| `NowPlayingController` (+ `RemoteCommandHandler`) | Lock-screen/Control-Center metadata, remote commands, idle-timer. |
| `ModelLoading` (+ `VoiceNameDeriver`, `VoiceSelection`) | Load Kokoro engine+voices off-main (GCD); publish `isModelLoaded`; own voice selection. |
| `TextIngesting` (+ `TextExtracting`, `SharedURLInbox`, `ContentLoader`) | Normalize/route a `ContentSource` → `IngestedDocument`; drain share-extension URL. |
| `SentenceAudioStore` | The `audioCache`/`skippedSentences` seam: `audioState(at:)`/`put`/`markSkipped`/`evict`/`reset`. |
| `SentenceAudioSynthesizer` | MLX/Kokoro synth (disk-cache-first) behind an interface; GCD-only, never throws. |
| `GenerationPipeline` | Lookahead producer loop feeding the store, throttled to `lookaheadCount` ahead of cursor. |
| `PlaybackControlling` (+ `PlaybackContentSource`, `AudioGraphControlling`) | Transport state machine + AVAudio graph/session; emits events instead of fan-out. |

**Existing protocols/types that already fit** (extend, do not reinvent): `SentenceAudioProvider` (scheduler's read seam — becomes a thin adapter over `SentenceAudioStore`), `AudioBufferPlayer` / `AVAudioPlayerNodeAdapter`, `GaplessSentenceScheduler`, `AudioDiskCache` (already off-device testable, temp-dir injectable), plus the DTOs `WordTiming`, `SentenceAudio`, `PlaylistItem`, `ListeningRecord`, `ReadingContent`, `ContentSource`.

## 3. The regeneration harness (what makes this "regenerative")

**Durable-artifact convention.** For every unit there are exactly two durable files plus the protocol declaration:

1. `docs/specs/<Unit>.md` — the contract.
2. `Tests/PagehumTests/<Unit>Tests.swift` — the behavior pin.
3. `Sources/.../<Unit>.swift` — the **disposable** protocol + concrete impl.

After extraction, the concrete impl is regenerable: you can delete `<Unit>.swift`'s implementation body and ask an LLM to regenerate it from `docs/specs/<Unit>.md` + the protocol + `<Unit>Tests.swift` — green tests prove the regeneration is correct.

**Spec template** (`docs/specs/<Unit>.md`):

```markdown
# <Unit>

## Purpose
<1-2 lines: the single responsibility>

## Protocol
```swift
<the exact Swift protocol signature(s) collaborators depend on>
```

## Inputs
- <every value/dependency injected in; note @MainActor requirements>

## Outputs
- <returned values, callbacks, AsyncStreams — NEVER "@Published field X">

## Invariants
- <numbered, each citing the source line/rule it pins,
   e.g. "MLX inference runs on DispatchQueue.global via withCheckedContinuation, never Task.detached">

## Failure modes
- <input → observable degraded behavior; note current bugs to preserve or fix>

## Non-goals
- <explicitly what this unit must NOT own — the anti-leak fence>

## Test manifest
- <bullet list mapping 1:1 to test cases in <Unit>Tests.swift>
```

**Layout:**

```
docs/specs/
  SentenceSegmenter.md  WordHighlightClock.md  ProgressStore.md
  ListeningStore.md     NowPlaying.md          ModelLoading.md
  TextIngest.md         SentenceAudioStore.md  GenerationPipeline.md
  PlaybackController.md
Sources/Pagehum/Units/
  <same basenames>.swift
Tests/PagehumTests/
  <same basenames>Tests.swift
  Fakes/  (FakeSynthesizer, FakeTextExtracting, FakeAudioGraph, ManualTicker, FixedClock, InMemoryModelContainer)
```

**Workflow per unit:** write spec → write characterization tests against *current* behavior (they must pass against the god-object first) → extract impl behind protocol → tests still green → *prove regenerability* by blanking the impl body and regenerating once (optional gate, recommended for the pure units).

## 4. Dependency matrix & extraction order

| Unit | Depends-on | Reads shared state | Writes shared state | Off-device | Risk |
|---|---|---|---|---|---|
| SentenceSegmenting | — | none | none | **full** | low |
| WordHighlightClock | (events from Playback) | `speed`,`bufferStartTime`,`currentTokens` | `currentTokenIndex`,`currentWordText`,`bufferStartTime`,`pauseElapsed` | **full** | medium |
| ProgressStoring | ContentLoader, NowPlaying | `progress`,`currentSentenceIndex`,`content` | `currentPlaylistItemID`,`savedConfirmation`, PlaylistItem rows | **full** | medium |
| ListeningStoring | (speed hook) | `speed`,`isPlaying` | `listeningAccumulator`,`listeningSessionStart` | **full** | medium |
| NowPlayingController | PlaybackControlling | `content`,`isPlaying`,`speed`,`currentSentenceIndex`,`sentences.count` | none | partial (sim) | medium |
| ModelLoading | VoiceSelection | UserDefaults, Bundle | `kokoroTTSEngine`,`voices`,`voiceNames`,`selectedVoice`,`isModelLoaded` | partial | medium |
| TextIngesting | Segmenter, ProgressStore, TextExtractor, Playback | `pendingSharedURL`,`content`,`sentences.count` | `content`,`sentences`,`isLoading`,`errorMessage`,`audioCache`,`skippedSentences` | partial | medium |
| SentenceAudioStore | — | none (owns them) | `audioCache`,`skippedSentences` | **full** | low |
| SentenceAudioSynthesizer | AudioDiskCache | `kokoroTTSEngine`,`voices` | none | device-only | high |
| GenerationPipeline | Store, Synthesizer, Scheduler | `currentSentenceIndex`,`sentences`,`selectedVoice` | store, `isGenerating`,`generationTask` | partial | high |
| PlaybackControlling | Scheduler, Pipeline, Store, all emit-targets | `sentences`,`isModelLoaded`,`currentSentenceIndex` | transport `@Published` + (today) sibling state | partial | high |

**Ordered extraction sequence** (each step is independently shippable — compiles + tests green — and shrinks ReaderModel):

| # | Step | Why here | ~LOC moved |
|---|---|---|---|
| 0 | Test target bootstrap | Nothing is safely extractable without characterization tests. | 0 (adds harness) |
| 1 | **SentenceSegmenting** | Already static/pure, zero shared state — the free win that validates the harness. | ~55 |
| 2 | **SentenceAudioStore** | Small, no external deps; landing it early lets steps 8–9 & 10 target it instead of raw dicts. | ~30 (+reroute) |
| 3 | **WordHighlightClock** | Fully off-device; reroute its ~9 mutation sites to `begin/pause/resume/setSpeed/reset` (playback still god, but calls the clock). | ~50 |
| 4 | **ProgressStoring + ListeningStoring** | Full off-device (in-memory `ModelContainer`); splits the two persistence siblings and cuts the `speed.didSet` accumulator recalc. | ~95 |
| 5 | **NowPlayingController + RemoteCommandHandler** | Contained MediaPlayer surface; breaks the remote↔playback cycle and centralizes idle-timer. | ~70 |
| 6 | **ModelLoading + VoiceNameDeriver + VoiceSelection** | Returns `LoadedModel`; stops writing `voiceNames`/`selectedVoice` as side effects. | ~45 |
| 7 | **TextIngesting + ContentLoader** | Returns `IngestedDocument`; hands persistence to step 4, stops clearing pipeline caches. | ~130 |
| 8 | **SentenceAudioSynthesizer** | The MLX boundary must exist behind an interface before the loop can be tested with a stub. | ~50 |
| 9 | **GenerationPipeline** | Now targets Store (step 2) + Synthesizer (step 8); loop logic becomes stub-testable. | ~90 |
| 10 | **PlaybackControlling + AudioGraphControlling** | The spine, last: every sibling it fans into already exists behind a protocol, so its writes become emitted events. | ~180 |

## 5. Step 0 — Test target bootstrap (prerequisite)

1. Add a `PagehumTests` unit-test bundle targeting the app.
2. **Off-device vs device.** Everything except MLX runs in a plain XCTest on a Mac: Foundation, `NaturalLanguage`, `AVAudioPCMBuffer`/`AVAudioFormat` construction, SwiftData (in-memory), and the `MediaPlayer`/`UIKit` surface (simulator only for the latter). **MLX is physical-device-only** — `KokoroTTS.generateAudio` over `MLXArray` voices cannot run in CI.
3. **Fake MLX behind a protocol.** Define `SentenceAudioSynthesizer` (Step 8) now, even before extracting the loop, and provide `FakeSynthesizer` returning canned `SentenceAudio` (a short silent `AVAudioPCMBuffer` + fixed `[WordTiming]`) or `nil` to exercise the skip path. This is what makes `GenerationPipeline` testable off-device without a device.
4. **Fakes to author up front** in `Tests/.../Fakes/`: `FixedClock: WordClockDateProvider`, `ManualTicker: HighlightTicker`, `FakeTextExtracting`, `FakeAudioGraph: AudioGraphControlling` (records `start()`/asserts `stop()` is **never** called), `InMemoryModelContainer` helper (`ModelConfiguration(isStoredInMemoryOnly: true)` for `PlaylistItem` + `ListeningRecord`).
5. **Characterization-first.** For each unit, tests are written to pass against the *current* god-object behavior (call the existing `ReaderModel` methods) before the extraction, then re-pointed at the new type. Preserve documented quirks (e.g. `splitIntoSentences` returning an oversize single 500-char token; `ctx.save()` swallowing errors via `try?`) — decide per-invariant whether to pin or fix, and record the decision in the spec's Failure modes.

## 6. Per-unit extraction playbook

### Step 1 — SentenceSegmenting
- **(a) Scope:** `splitIntoSentences(_:)` (L836), `splitLongSentence(_:)` (L857, stays internal), `maxSentenceLength = 400` (L834). `prepareText` does **not** move — it belongs to ContentLoader (Step 7).
- **(b) Protocol:**
  ```swift
  protocol SentenceSegmenting {
      var maxSentenceLength: Int { get }
      func splitIntoSentences(_ text: String) -> [String]
  }
  struct DefaultSentenceSegmenter: SentenceSegmenting { init(maxSentenceLength: Int = 400) }
  ```
- **(c) State cut:** none — inputs `String`, output `[String]`. No shared state crosses the seam. `maxSentenceLength` becomes an init parameter (single source of truth), not a re-hardcoded constant in callers.
- **(d) Characterization tests:** empty/whitespace → `[]`; 400 kept / 401 split; clause split honors the ≥80-char gate; comma-free >400 word-split with no mid-word break; 500-char single token returned oversize; order preserved; NLTokenizer-empty fallback → `[text]`.
- **(e) Done:** `DefaultSentenceSegmenter` injected into `ReaderModel`; `prepareText` calls `segmenter.splitIntoSentences`. Tests green.
- **(f) Replaceability check:** **Yes, fully.** Zero leaks. This is the reference case.

### Step 2 — SentenceAudioStore
- **(a) Scope:** the stored `audioCache: [Int: SentenceAudio]` (L103) and `skippedSentences: Set<Int>` (L104), plus the read logic of the `SentenceAudioProvider.audioState(at:)` conformance (L898-902) and the eviction in `handleSentenceStarted` (L724).
- **(b) Protocol:**
  ```swift
  enum SentenceAudioState { case pending, ready(SentenceAudio), skipped }
  @MainActor protocol SentenceAudioStore: AnyObject {
      func audioState(at index: Int) -> SentenceAudioState
      func put(_ audio: SentenceAudio, at index: Int)
      func markSkipped(_ index: Int)
      func evict(before index: Int)
      func reset()
  }
  ```
- **(c) State cut:** `audioCache`/`skippedSentences` stop being `ReaderModel` fields. The existing `SentenceAudioProvider` conformance becomes a thin adapter reading `store.audioState(at:)`. **Invariant preserved:** cache + skipped are always cleared together — enforced by a single `reset()` (replaces the ~6 scattered clear sites at L86-88, 278, 449/469-470, 495-507, 323-324/339, 252, which are rewired in later steps to call `store.reset()`).
- **(d) Tests:** `put` then `audioState == .ready`; `markSkipped` → `.skipped`; unknown → `.pending`; `evict(before:)` drops lower indices only; `reset()` empties both sets atomically.
- **(e) Done:** all six lifecycle clear-sites call `store.reset()`; `handleSentenceStarted` calls `store.evict(before:)`.
- **(f) Replaceability check:** **Yes.** Small, pure, no external deps. This is the linchpin that de-shares state between Generation (writer) and Playback/Scheduler (reader) — landing it now de-risks Steps 9–10.

### Step 3 — WordHighlightClock
- **(a) Scope:** `bufferStartTime` (L114), `wordTimer` (L115), `currentTokens` (L113), `pauseElapsed` (L116), `startWordTimer` (L748), `stopWordTimer` (L755), `updateWordHighlight` (L760-781), and the **anchor-recalc half** of `speed.didSet` (L69-72 only — the L73-76 listening recalc goes to Step 4).
- **(b) Protocol:**
  ```swift
  protocol WordClockDateProvider { func now() -> Date }
  protocol HighlightTicker: AnyObject {
      func start(interval: TimeInterval, _ onTick: @escaping () -> Void); func stop()
  }
  @MainActor protocol WordHighlightClock: AnyObject {
      var onWordChanged: ((_ tokenIndex: Int, _ wordText: String) -> Void)? { get set }
      func begin(tokens: [WordTiming]?, leadingSilence: TimeInterval)
      func pause(); func resume(); func setSpeed(_ newSpeed: Float); func reset()
  }
  ```
- **(c) State cut:** `bufferStartTime`/`pauseElapsed`/`currentTokens` become **clock-internal**. `currentTokenIndex`/`currentWordText` (`@Published`, still on the root for Views) are written **only** via `onWordChanged`; every direct reset (seek L329-330, stop L504-505, `handleSentenceStarted` L715-716, `handlePlaybackFinished` L734) is rerouted through `clock.reset()`/`clock.begin(...)`. The clock holds its own `speed` copy via `setSpeed` (no per-tick read of `ReaderModel.speed`).
- **(d) Tests (with `FixedClock` + `ManualTicker`):** `begin`+advance→emits `(0,"Hello")` then `(1,"world")`; dedup emits once per transition; `setSpeed(2.0)` preserves elapsed audio-seconds; pause/resume continuity (advance 10s while paused → resume at frozen offset); `leadingSilence` keeps index -1 while elapsed negative; `reset()` emits `(-1,"")` once; nil/`start==nil` tokens skipped; backward index allowed after speed-down.
- **(e) Done:** playback methods call `clock.begin/pause/resume/setSpeed/reset`; no method writes `bufferStartTime`/`pauseElapsed` directly.
- **(f) Replaceability check:** **Yes** once all direct writers of `currentTokenIndex/currentWordText` are rerouted. *Still leaking until then:* if any caller bypasses the clock, the `@Published` and the clock's "last emitted index" diverge — the done-criterion is "zero direct writers remain."

### Step 4 — ProgressStoring + ListeningStoring
- **(a) Scope:** `saveProgressNow` (L364-377), `saveToPlaylist` (L344-362), the **insert half** of `saveForLater` (L283-310, network half → Step 7), `currentPlaylistItemID` (L59). Sibling: `accumulateListeningTime`/`saveListeningTime`/`startListeningSaveTimer`/`stopListeningSaveTimer` + `listeningSessionStart`/`listeningAccumulator`/`listeningSaveTimer`, and the L73-76 accumulator recalc from `speed.didSet`.
- **(b) Protocol:**
  ```swift
  protocol ProgressStoring: AnyObject {
      var activeItemID: PersistentIdentifier? { get set }
      @discardableResult func insertActiveItem(title: String, sourceURL: String?, sourceType: String, fullText: String) -> PersistentIdentifier?
      @discardableResult func insertQueuedItem(title: String, sourceURL: String?, sourceType: String, fullText: String) -> PersistentIdentifier?
      func saveProgress(for id: PersistentIdentifier, progress: Double, sentenceIndex: Int)
      func saveActiveProgress(progress: Double, sentenceIndex: Int)
  }
  protocol ListeningStoring: AnyObject {
      func startSession(); func pauseSession(); func flush()
      func rescale(speed: Float)   // replaces the speed.didSet L73-76 recalc
  }
  ```
- **(c) State cut:** `saveProgressNow`'s reads of `progress`/`currentSentenceIndex` become **method parameters** (playback pushes values). The inline `updateNowPlayingInfo()` call is **removed** — the caller (or a `didSaveProgress` hook) triggers NowPlaying (Step 5). `currentPlaylistItemID` becomes `activeItemID` (protocol-owned). Listening accumulator stops being touched from `speed.didSet` — replaced by `rescale(speed:)`.
- **(d) Tests (in-memory `ModelContainer`, injected clock):** `insertActiveItem` sets `activeItemID` + `textPreview == first 200 chars`; `saveActiveProgress(0.5)` promotes `queued→inProgress`; `1.0`→`completed`; completed not regressed by later `0.3`; `insertQueuedItem` leaves `activeItemID` untouched; nil `modelContext`→no-op; deleted-row id→silent no-op; **ListeningStoring:** two same-day saves → one `ListeningRecord` (unique `dateString`); `secondsListened == elapsed*speed` within tolerance.
- **(e) Done:** playback calls `progress.saveActiveProgress(...)` + `listening.startSession/pauseSession/flush`; `speed` change calls `listening.rescale`.
- **(f) Replaceability check:** **Yes.** Remaining watch item: `modelContext` is late-injected (nil before `Pagehum` wires it) — tests must reproduce by injecting a context; ordering coupling is documented, not leaked.

### Step 5 — NowPlayingController + RemoteCommandHandler
- **(a) Scope:** `setupRemoteTransportControls()`, `updateNowPlayingInfo()` (+ non-iOS stub), the `nowPlayingInfo = nil` tail of `stop()`, and the five scattered `isIdleTimerDisabled` toggles (play, pause, stop, `handlePlaybackFinished`, and play()'s two engine-fail returns).
- **(b) Protocol:**
  ```swift
  struct NowPlayingSnapshot { let title: String; let isPlaying: Bool; let rate: Double; let sentenceIndex: Int; let sentenceCount: Int }
  @MainActor protocol RemoteCommandHandler: AnyObject {
      func remotePlay(); func remotePause(); func remoteTogglePlayPause(); func remoteSkipForward(); func remoteSkipBackward()
  }
  @MainActor protocol NowPlayingController: AnyObject {
      func activate(handler: RemoteCommandHandler)
      func update(_ snapshot: NowPlayingSnapshot); func clear(); func setIdleTimerDisabled(_ disabled: Bool)
  }
  ```
- **(c) State cut:** `updateNowPlayingInfo`'s five inline model reads become a caller-built `NowPlayingSnapshot`. The remote↔playback cycle is broken: commands route through `RemoteCommandHandler` (implemented by `PlaybackControlling`), metadata flows the other way as a snapshot. Idle-timer funnels through `setIdleTimerDisabled(_:)`.
- **(d) Tests (fake handler + injectable idle-timer sink):** `isPlaying=true,speed=1.5 → rate 1.5`; paused → `0.0`; `sentenceCount=0 → duration 1`; nil title → `"Pagehum"`; simulate `playCommand → handler.remotePlay()` once; skip commands register `preferredIntervals == [20]`; `clear()` → `nowPlayingInfo == nil`; each command hops `@MainActor`.
- **(e) Done:** `speed.didSet`, `saveProgress` callers, and `play()` push snapshots; no method reads model state for now-playing.
- **(f) Replaceability check:** **Yes** for the snapshot mapping + command routing (off-device via fakes). MP*/UIKit assignment is simulator-verified, not CI — acceptable since it's a thin OS shim.

### Step 6 — ModelLoading + VoiceNameDeriver + VoiceSelection
- **(a) Scope:** `loadModel()` (L174-197), `kokoroTTSEngine` (L39), `voices` (L43), `isModelLoaded` (L45); the pure tail (L188-195) → `VoiceNameDeriver`. `voiceNames`/`selectedVoice` ownership moves to `VoiceSelection`.
- **(b) Protocol:**
  ```swift
  struct LoadedModel { let engine: KokoroTTS; let voices: [String: MLXArray]; let voiceNames: [String] }
  protocol ModelLoading: AnyObject {
      var isModelLoaded: Bool { get }
      func load() async throws -> LoadedModel   // GCD + withCheckedContinuation; idempotent
  }
  enum VoiceNameDeriver {
      static func displayNames(from voiceKeys: [String]) -> [String]
      static func defaultVoice(available: [String], stored: String) -> String
  }
  ```
- **(c) State cut:** `loadModel` returns `LoadedModel` instead of writing four foreign fields. `selectedVoice`/`voiceNames` are set by `VoiceSelection` from the result — this removes the fragile `selectedVoice.didSet` ordering dependency (L81-90) at startup. `engine`/`voices` are handed to `SentenceAudioSynthesizer` (Step 8), not read as shared props by generation.
- **(d) Tests:** `VoiceNameDeriver.displayNames(["af_heart.npy","bm_george.npy"]) == ["af_heart","bm_george"]`; `"af.v2.npy" → "af"` (pins `split(".")[0]`); `defaultVoice` af-prefix preference, first-fallback, empty-fallback, honors stored; with a stub `ModelLoading` returning fixed `LoadedModel`, `isModelLoaded` flips true and the `play()` gate opens.
- **(e) Done + fixes to fold in:** throw on missing bundle URL instead of force-unwrap (L175-176); set `isModelLoaded` true only when `voices` non-empty (closes the loaded-but-no-voices latent bug L196/L181).
- **(f) Replaceability check:** **Partial by nature** — real MLX load is device-only; the deterministic tail + gate are fully regenerable. Injecting `ModelLoading` lets downstream be tested off-device against a stub.

### Step 7 — TextIngesting + ContentLoader
- **(a) Scope:** `load(from:)`, `loadURL`, `loadPDF`, `loadText`, `prepareText`/`prepareTextPublic` (the split call only), `saveForLater` (extraction half), `saveToPlaylist` mapping, `handleOpenURL`, `checkForSharedURL`, `loadPendingSharedURL`, `extractor`, `appGroupID`/`sharedURLKey`.
- **(b) Protocol:**
  ```swift
  protocol TextExtracting: AnyObject { func extract(from source: ContentSource) async throws -> ReadingContent }
  protocol SharedURLInbox: AnyObject { func drainSharedURL() -> String?; func parseDeepLink(_ url: URL) -> String? }
  struct IngestedDocument { let content: ReadingContent; let sentences: [String]; let source: ContentSource }
  protocol TextIngesting: AnyObject {
      func ingest(rawURL: String) async throws -> IngestedDocument
      func ingest(pdf url: URL) async throws -> IngestedDocument
      func ingest(text: String) async throws -> IngestedDocument
      func extractForSaving(rawURL: String) async throws -> ReadingContent
      func normalizedURL(from raw: String) -> URL?
  }
  ```
- **(c) State cut:** ingestion returns `IngestedDocument`; a small `ReaderStateApplier` on the root writes `content`/`sentences`/`isLoading`/`errorMessage` and seeds resume `currentSentenceIndex`/`progress`. `prepareText` **stops** clearing `audioCache`/`skippedSentences` — instead the applier fires a `contentReplaced` event → `store.reset()` + `pipeline.stop()`. `load()`'s inline `stop()` becomes a caller-sequenced `willReplaceContent`. Persistence hands off to `ProgressStoring` (Step 4). **New required invariant:** serialize in-flight extractions (single `WKWebView`) to close the concurrent-clobber hazard.
- **(d) Tests (fake `TextExtracting`, injected `UserDefaults` suite):** `normalizedURL` prepends `https://`, trims, `nil` on garbage; `ingest(text:"   ")` rejects with "Please enter some text"; `handleOpenURL(pagehum://open?url=...)` sets pending, wrong scheme/host ignored; `checkForSharedURL` one-shot drain (second call nil); mapping `.url→("url",absoluteString)`, `.pdf→("pdf",lastPathComponent)`, `.text→("text",nil)`; extractor `timedOut` → `errorMessage`, `isLoading` reset; **concurrency regression:** two overlapping `ingest()` not cross-contaminated.
- **(e) Done:** Views call the applier; no ingestion method writes pipeline/reader `@Published` in place.
- **(f) Replaceability check:** **Partial** (WKWebView/PDFKit behind `TextExtracting` fakes). Leaks closed: pipeline-cache clearing, direct reader writes, embedded SwiftData inserts, unserialized extractor.

### Step 8 — SentenceAudioSynthesizer
- **(a) Scope:** `generateSentenceAudio(for:format:voiceKey:lang:)` (L785-830) — the disk-cache-first read (`AudioDiskCache.load` L792), MLX `generateAudio` inside the GCD closure (L786-787), PCM packing, `MToken→WordTiming` map, fire-and-forget `AudioDiskCache.store` (L821).
- **(b) Protocol:**
  ```swift
  protocol SentenceAudioSynthesizer: Sendable {
      func synthesize(text: String, voiceKey: String, language: Language, format: AVAudioFormat) async -> SentenceAudio?
  }
  ```
- **(c) State cut:** `kokoroTTSEngine`/`voices` are captured **inside the synthesizer** (from `LoadedModel`), not from the model in a closure. Returns `SentenceAudio?` (`nil` = skip). **Invariant preserved verbatim:** inference + disk I/O run on `DispatchQueue.global(qos:.userInitiated)` via `withCheckedContinuation`, **never** `Task.detached` or the cooperative pool.
- **(d) Tests:** off-device via `FakeSynthesizer` for the loop (Step 9). Device-only: real `synthesize` returns non-empty 24 kHz mono Float32 buffer; `AudioDiskCache` round-trip (already off-device) matches `frameLength`+tokens; corrupt/missing json → `nil` miss. Failure paths: engine nil, missing voice, empty audio, alloc fail, `tooManyTokens` → all `nil`.
- **(e) Done:** the loop calls `synthesizer.synthesize`; no MLX symbol appears outside this type.
- **(f) Replaceability check:** **Partial (device-only by nature)** — but the interface makes *everything above it* regenerable off-device.

### Step 9 — GenerationPipeline
- **(a) Scope:** `startPipeline()` (L666-706), `generationTask` (L105), `lookaheadCount` (L106), `isGenerating` (L53), `audioFormat`/`sampleRate` (L123-126).
- **(b) Protocol:**
  ```swift
  @MainActor protocol GenerationPipeline: AnyObject {
      func start(from startIndex: Int); func stop()
      var onProduced: ((_ index: Int) -> Void)? { get set }
      var onGeneratingChanged: ((Bool) -> Void)? { get set }
  }
  ```
- **(c) State cut:** writes go to `SentenceAudioStore` (Step 2), not raw dicts. The playback cursor (`currentSentenceIndex`) becomes an **input** advanced by the scheduler, read as a throttle bound only. `scheduler.notifyAvailable()` (L701) → `onProduced` callback. `isGenerating` `@Published` write → `onGeneratingChanged`. **Invariants preserved:** ≤`lookaheadCount` ahead (200ms throttle L683-685); at most one `generationTask` (cancel+nil before restart L667-668); cache-hit fast path awaits `Task.yield()` (L678-679); speed 1.0 always (L800).
- **(d) Tests (FakeSynthesizer, real Store):** cursor pinned at 0 + 5 sentences → exactly `lookaheadCount` (3) entries then blocks; advance cursor → one more; `nil` at idx 2 → `markSkipped(2)`, proceeds to 3; pre-populated store entry → synth not invoked, loop yields; `stop()` halts synth calls + `onGeneratingChanged(false)`; `onProduced` fires once per index ascending; restart re-seeds; voiceKey/Language mapping (`af_*→enUS+".npy"`, `bf_*→enGB`).
- **(e) Done:** all six lifecycle sites drive `pipeline.start/stop` + `store.reset`, never poke fields.
- **(f) Replaceability check:** **Yes for the loop** (stub-testable). Device-only synth is isolated below the seam. Highest-value regenerable unit given it was the most entangled producer.

### Step 10 — PlaybackControlling + AudioGraphControlling
- **(a) Scope:** the AVAudio graph (`audioEngine`/`playerNode`/`timePitch`), `scheduler` wiring, `speed` `@Published`, `isPlaying`/`isPaused`, `play`/`pause`/`stop`/`togglePlayback`/`seekToSentence`/`skip*`, `sentenceIndexBySkipping`, `estimatedCharsPerSecond`, `ensureAudioSessionActive`, `setupAudioSessionObservers`, `cleanup`, and the graph/session build in `init`.
- **(b) Protocol:**
  ```swift
  enum PlaybackState { case playing, paused, stopped, finished }
  @MainActor protocol PlaybackControlling: AnyObject {
      var isPlaying: Bool { get }; var isPaused: Bool { get }; var speed: Float { get set }
      func play(); func pause(); func stop(); func togglePlayback()
      func seekToSentence(_ index: Int); func skipForward(); func skipBackward()
      func ensureEngineRunning(); func cleanup()
      var onStateChanged: ((PlaybackState) -> Void)? { get set }
      var onSentenceBecameAudible: ((_ index: Int, _ audio: SentenceAudio) -> Void)? { get set }
      var onSeek: ((_ index: Int) -> Void)? { get set }
  }
  @MainActor protocol PlaybackContentSource: AnyObject {
      var isModelReady: Bool { get }; var sentenceCount: Int { get }
      var currentSentenceIndex: Int { get }; func characterCount(ofSentence index: Int) -> Int
  }
  @MainActor protocol AudioGraphControlling: AnyObject {
      var isRunning: Bool { get }; func start() throws; func setRate(_ rate: Float); func activateSession()
      // deliberately NO stop()/teardown — enforces never-stop-engine
  }
  ```
- **(c) State cut (the big one):** every synchronous fan-out becomes an emitted event. `speed.didSet` → `setRate` + `onSpeedChanged` consumed by `clock.setSpeed` (Step 3), `listening.rescale` (Step 4), NowPlaying snapshot (Step 5) — no longer mutates `bufferStartTime`/`listeningAccumulator`/now-playing inline. `play/pause/stop/seek` emit `onStateChanged`; `handleSentenceStarted`/`handlePlaybackFinished` emit `onSentenceBecameAudible`/`.finished` and let siblings own `currentTokenIndex`/`currentWordText`/`progress`. Cache clears → `store.reset()`+`pipeline.start(from:)`. `isModelLoaded`/`sentences` read via `PlaybackContentSource`. AVAudioEngine/session hide behind `AudioGraphControlling`.
- **(d) Tests (Fake graph asserts `stop()` never called; mock scheduler):** `sentenceIndexBySkipping(20,forward:true)` accumulates `characterCount` until ≥`20*13`, clamps at `count-1`; forward:false symmetric, clamps 0; `play()` no-op when `!isModelReady || count==0`; resume path (paused) vs fresh path (cache cleared, `scheduler.start(from:currentSentenceIndex)`); pause→play rebuilds elapsed via injected clock; seek-while-paused sets `isPaused=false`, no auto-start; out-of-range seek no-op; `stop()` resets index/progress but **mock engine.stop() never invoked**; `speed` setter drives injected `timePitch.rate`; `onFinished` flips flags + emits `.finished` once.
- **(e) Done:** `ReaderModel` transport methods forward to `PlaybackControlling`; siblings react to events; no cross-unit field writes remain.
- **(f) Replaceability check:** **Partial** (AVAudioEngine/session behind `AudioGraphControlling`, scheduler already mockable). All five historical fan-outs are now events → the spine is regenerable from spec+protocol+tests.

## 7. What remains in ReaderModel (the composition root)

After Step 10, `ReaderModel` retains only:

- **Shared `@Published` UI state** that multiple Views bind to and that no single unit exclusively owns: `isPlaying`, `isPaused`, `progress`, `currentSentenceIndex`, `currentTokenIndex`, `currentWordText`, `content`, `isLoading`, `errorMessage`, `voiceNames`, `selectedVoice`, `isModelLoaded`, `isGenerating`, `savedConfirmation`, `pendingSharedURL`. (Each is now *fed* by exactly one unit's callback/event — the root is a projection surface, not a state owner.)
- **DI wiring in `init`:** construct the ~11 units, inject dependencies (`ModelLoading`→synthesizer→pipeline→store→scheduler; clock/progress/listening/nowplaying), and connect callbacks (`clock.onWordChanged → currentTokenIndex/currentWordText`, `pipeline.onGeneratingChanged → isGenerating`, `playback.onStateChanged → isPlaying/isPaused` + `progress.saveActiveProgress` + `listening` + `nowplaying`, `playback.onSentenceBecameAudible → clock.begin`).
- **Thin forwarding methods** for Views (`play()` → `playback.play()`, `loadURL` → `ingest` + apply, `seek` → `playback.seekToSentence`) and the `PlaybackContentSource`/`RemoteCommandHandler`/`SentenceAudioProvider` conformances (pure adapters).

**Rough final LOC: ~120–160** (from ~903). The residual is wiring + projection only; no algorithm, no I/O, no MLX.

## 8. Risks, sequencing hazards & rollback

**Honored invariants (never violated by any step):**
- **MLX-on-GCD:** confined to `SentenceAudioSynthesizer` (Step 8) and `ModelLoading` (Step 6); both keep `DispatchQueue.global(qos:.userInitiated)` + `withCheckedContinuation`. No step introduces `Task.detached` on an MLX path. A dedicated test in Step 10's fakes asserts synthesis is never invoked on the main actor.
- **Never-stop-engine:** `AudioGraphControlling` (Step 10) exposes **no** `stop()`/teardown; `cleanup()==stop()` acts on the scheduler's player node only. A fake-graph test asserts `engine.stop()` is never called across play/pause/stop/seek.
- **Singleton persists across navigation:** the root stays a singleton; no unit calls `cleanup()` on view disappear — documented in `PlaybackController.md` Non-goals.

**Trickiest cuts & safe sequencing:**
1. **Word-highlight clock ↔ playback ↔ generation coupling.** `bufferStartTime`/`pauseElapsed` are shared between `speed.didSet`, `play()` resume, `pause()`, seek, and `handleSentenceStarted`. **Sequence:** extract the clock (Step 3) and reroute its writers *while playback is still the god-object* — the god methods simply call `clock.begin/pause/resume/setSpeed/reset`. Only in Step 10 do those calls become event subscriptions. This two-phase move means the clock is validated in isolation before the spine is touched.
2. **`audioCache`/`skippedSentences` shared between generation (writer) and playback/scheduler (reader/evictor).** **Sequence:** land `SentenceAudioStore` **early (Step 2)** and reroute all ~6 clear sites + the `SentenceAudioProvider` read + `handleSentenceStarted` evict to it *before* extracting either producer or consumer. By the time Steps 9 and 10 run, neither reaches into the other's dictionary — they share a protocol, not a field.
3. **`speed.didSet` fusing four concerns** (`timePitch.rate`, clock anchor recalc, listening accumulator recalc, now-playing refresh). Split incrementally: Step 3 removes the anchor recalc, Step 4 removes the accumulator recalc, Step 5 removes now-playing; Step 10 finally reduces the setter to `setRate` + `onSpeedChanged`. Each removal is independently green.
4. **`ModelLoading` writing `selectedVoice` → `selectedVoice.didSet` (L81-90).** Today it's safe only because the didSet early-returns while `!isPlaying` at startup — a fragile ordering dependency. Step 6 makes `VoiceSelection` set the initial voice from `LoadedModel` *without* triggering a pipeline restart, removing the implicit ordering contract.

**Rollback.** Every step ships behind a protocol and is independently revertible: if a step regresses, revert that unit's `Sources/.../<Unit>.swift` and its wiring commit; the god-object method it replaced is restored and the injected protocol falls back to `ReaderModel`'s own conformance. Because each step is gated on "compiles + tests green + ReaderModel LOC measurably down," a bad step is caught before the next begins, and the durable `docs/specs/<Unit>.md` + `<Unit>Tests.swift` survive the revert — you regenerate the impl rather than re-reasoning the contract.
