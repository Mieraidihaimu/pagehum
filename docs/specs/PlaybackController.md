# PlaybackController

## Purpose
Transport state machine for TTS playback: owns the AVAudio graph/session lifecycle and drives the scheduler + generation pipeline through play/pause/stop/seek/skip, translating every historical synchronous fan-out (`speed.didSet`, sentence-started, finished, seek) into emitted events consumed by sibling units.

## Protocol
```swift
enum PlaybackState { case playing, paused, stopped, finished }

@MainActor protocol PlaybackControlling: AnyObject {
    var isPlaying: Bool { get }
    var isPaused: Bool { get }
    var speed: Float { get set }

    func play()
    func pause()
    func stop()
    func togglePlayback()
    func seekToSentence(_ index: Int)
    func skipForward()
    func skipBackward()

    func ensureEngineRunning()
    func cleanup()

    // Fan-outs → events (no unit reaches into ReaderModel's @Published fields)
    var onStateChanged: ((PlaybackState) -> Void)? { get set }
    var onSentenceBecameAudible: ((_ index: Int, _ audio: SentenceAudio) -> Void)? { get set }
    var onSeek: ((_ index: Int) -> Void)? { get set }
    var onSpeedChanged: ((Float) -> Void)? { get set }
}

@MainActor protocol PlaybackContentSource: AnyObject {
    var isModelReady: Bool { get }
    var sentenceCount: Int { get }
    var currentSentenceIndex: Int { get }
    func characterCount(ofSentence index: Int) -> Int
}

@MainActor protocol AudioGraphControlling: AnyObject {
    var isRunning: Bool { get }
    func start() throws
    func setRate(_ rate: Float)
    func activateSession()
    // deliberately NO stop()/teardown — enforces never-stop-engine
}
```
`PlaybackControlling` also conforms to `RemoteCommandHandler` (owned by `NowPlaying.md`, Step 5): `remotePlay/remotePause/remoteTogglePlayPause/remoteSkipForward/remoteSkipBackward` are thin forwarders to `play/pause/togglePlayback/skipForward/skipBackward` (today the `MPRemoteCommandCenter` closures at ReaderModel.swift L561-590).

## Inputs
- `graph: AudioGraphControlling` — the concrete impl wraps the AVAudio graph built in `init` (ReaderModel.swift L129-139: `AVAudioEngine`, `AVAudioPlayerNode`, `AVAudioUnitTimePitch`; `playerNode → timePitch → mainMixerNode`, format `AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)`) and the session build (L159-169). `@MainActor`.
- `scheduler: GaplessSentenceScheduler` (`@MainActor`, EXISTS) — this unit calls `start(from:)`/`pause()`/`resume()`/`stop()`/`notifyAvailable()` and wires `scheduler.onSentenceStarted`/`scheduler.onFinished` to its own handlers (L145-155, `handleSentenceStarted` L712, `handlePlaybackFinished` L731).
- `pipeline: GenerationPipeline` (Step 9) — `start(from:)`/`stop()`, replacing the inline `startPipeline()`/`generationTask` control at L666-706, L448-451, L495-497, L321-322.
- `store: SentenceAudioStore` (Step 2) — `reset()` and `evict(before:)` only; replaces the raw `audioCache = [:]; skippedSentences = []` and the `handleSentenceStarted` eviction loop (L724).
- `content: PlaybackContentSource` — read-only view of `isModelLoaded` (L422), `sentences.count` (L422, L531-548), `currentSentenceIndex` (L471, L534). Playback never owns the sentence array.
- Initial `speed` seed: `UserDefaults.standard.float(forKey: "playbackSpeed")` clamped to fallback `1.0` (L61, L141, L157).
- `estimatedCharsPerSecond = 13` (L529) — used for skip budgeting; init-injectable constant, single source of truth.
- The whole unit is `@MainActor` (matches the `@MainActor final class ReaderModel`, L36).

## Outputs
- `onStateChanged(PlaybackState)` — `.playing` on fresh start and resume (L441/L467), `.paused` on `pause()` (L482-483), `.stopped` on `stop()` (L498-499), `.finished` from `handlePlaybackFinished` (L732-733). The root projects these onto shared `@Published var isPlaying`/`isPaused`.
- `onSentenceBecameAudible(index, audio)` — emitted from `handleSentenceStarted` (L712); carries `SentenceAudio` whose `tokens: [WordTiming]?` (L28-34) feed `WordHighlightClock.begin(...)`. The root also uses `index` to set `currentSentenceIndex`/`progress` and call `ProgressStoring.saveActiveProgress`.
- `onSeek(index)` — emitted by `seekToSentence` (L314) so siblings can `clock.reset()` and persist the seeked position.
- `onSpeedChanged(Float)` — emitted from the `speed` setter (L61-78); consumed by `WordHighlightClock.setSpeed` (anchor recalc, was L69-72), `ListeningStoring.rescale` (accumulator recalc, was L73-76), and the NowPlaying snapshot (was `updateNowPlayingInfo()` L77).
- Side effect: persists `speed` to `UserDefaults["playbackSpeed"]` (L64) and drives `graph.setRate` (was `timePitch.rate = speed`, L63).
- Drives `scheduler` and `pipeline`; writes to the audio cache only through `store.reset()` / `store.evict(before:)`.

## Invariants
1. **Never stop the engine.** `AudioGraphControlling` exposes no `stop()`/teardown. `cleanup()` == `stop()` (L550-552) and both only stop the player node, via `scheduler.stop()` → `AudioBufferPlayer.stop()` → `playerNode.stop()` (GaplessSentenceScheduler.swift L109-113; AudioBufferPlayer.swift L48). PIN (CLAUDE.md "Never stop `audioEngine`"; REFACTOR_PLAN §8).
2. **Engine lives for the model's lifetime.** `play()`/resume only (re)start the engine when `!graph.isRunning` (was `if !audioEngine.isRunning { try? audioEngine.start() }`, L428-438, L456-465, L338); `ensureEngineRunning()` folds `ensureAudioSessionActive()` (L607-615) + this guarded start. PIN.
3. **Graph topology & speed model are fixed.** `playerNode → timePitch → mainMixerNode`, 24 kHz mono Float32 (L134-139). Speed is applied via `timePitch.rate` at playback time, never at generation (generation always uses `speed: 1.0`, L800). `setRate` mirrors L63. PIN.
4. **Singleton persists across navigation.** No View may call `cleanup()`/`stop()` on disappear; only the user or new-content load stops playback (CLAUDE.md "Views must NOT call `cleanup()`"; REFACTOR_PLAN §8). PIN (fenced in Non-goals).
5. **`audioCache` & `skippedSentences` are cleared together, atomically.** Every clear site (L87, L278, L324, L469, L507) becomes a single `store.reset()`; `handleSentenceStarted`'s "evict already-played" loop (L724) becomes `store.evict(before: index)`. PIN (CLAUDE.md "Always clear both together").
6. **At most one in-flight producer per start.** Before any fresh start or teardown, cancel generation + `scheduler.stop()` (L448-451, L495-497, L321-322); a fresh start is always preceded by `pipeline.stop()`. PIN.
7. **Resume ≠ fresh start.** When `isPaused` is true, `play()` resumes without clearing the store: `graph`-restart-if-needed → `scheduler.resume()` → emit `.playing` (L426-446). A fresh `play()` clears the store and does `scheduler.start(from: content.currentSentenceIndex)` + `pipeline.start(from:)` (L467-471). PIN.
8. **Seek collapses paused→stopped.** `seekToSentence` sets `isPaused = false` (L327) so the next `play()` is fresh; it only auto-resumes scheduler + pipeline when playback `wasPlaying` (L316, L335-341); out-of-range indices are a guarded no-op (L315). PIN.
9. **`speed` setter is de-fused.** Only `graph.setRate` + `UserDefaults` persistence stay in-unit; the three formerly-fused recalcs (`bufferStartTime` L69-72, `listeningAccumulator` L73-76, `updateNowPlayingInfo` L77) leave as `onSpeedChanged`. The `speed > 0` guard is preserved (L69). FIX (split the four-concern `didSet`; REFACTOR_PLAN §8 hazard 3).
10. **Skip budgeting.** `skipForward`/`skipBackward` target `sentenceIndexBySkipping(seconds: 20, forward:)`: accumulate `characterCount(ofSentence:)` until `≥ 20 * estimatedCharsPerSecond` (= 260), clamped to `[0, sentenceCount-1]` (L519-548). PIN.
11. **No MLX / no synthesis here.** This unit references no `kokoroTTSEngine`, `voices`, or `generateSentenceAudio` — MLX stays confined to `SentenceAudioSynthesizer` (Step 8) below the pipeline seam. PIN.
12. **Play is gated.** `play()` is a no-op unless `content.isModelReady && content.sentenceCount > 0` (L422). PIN.

## Failure modes
- `graph.start()` throws (engine won't start) → `play()` aborts cleanly: `isPlaying = false`, `isPaused = false`, idle-timer re-enabled, no `.playing` emitted (L429-437 resume path, L457-464 fresh path). PIN.
- Seek index `< 0` or `≥ sentenceCount` → silent no-op (L315). PIN.
- `play()` before model loaded or with zero sentences → silent no-op (L422). PIN.
- **Quirk (PIN):** any seek — even a 1-sentence skip — drops all cached audio and forces regeneration (`store.reset()` + `pipeline.start(from:)`, was L318-324). The L318-319 comment noted this predates the disk cache; the disk cache now re-hydrates cheaply, so the behavior is preserved rather than special-cased.
- **Quirk (PIN):** `stop()` zeroes `currentSentenceIndex`/`progress` (L503-506) **without** first persisting progress (unlike `pause()`, which calls `saveProgressNow()` at L491). In-session resume position is lost on an explicit stop / new-content load. Documented, not fixed — the plan does not call for a change here.
- Late completions after `stop()` are ignored by the scheduler (`guard isActive`, GaplessSentenceScheduler.swift L162), so a buffer finishing after teardown cannot re-fire `onStateChanged`. PIN.

## Non-goals
- **Word-highlight timing** (`currentTokenIndex`, `currentWordText`, `bufferStartTime`, `wordTimer`, `pauseElapsed`, `updateWordHighlight`) → `WordHighlightClock` (Step 3). Playback emits `onSentenceBecameAudible`/`onSpeedChanged`/state events; it computes no token index.
- **Audio synthesis & MLX** (`generateSentenceAudio`, `kokoroTTSEngine`, `voices`) → `SentenceAudioSynthesizer` (Step 8) + `GenerationPipeline` (Step 9). Playback only calls `pipeline.start/stop`.
- **Cache contents** (`audioState`/`put`/`markSkipped`) → `SentenceAudioStore` (Step 2). Playback touches it only via `reset()`/`evict(before:)`.
- **SwiftData persistence & listening time** (`saveProgressNow`, `accumulate/saveListeningTime`, listening timers, `currentPlaylistItemID`) → `ProgressStoring` + `ListeningStoring` (Step 4), driven by the root from playback events.
- **Now-playing metadata, remote-command registration, idle-timer toggling** (`setupRemoteTransportControls`, `updateNowPlayingInfo`, `MPNowPlayingInfoCenter`, `isIdleTimerDisabled`) → `NowPlayingController` + `RemoteCommandHandler` (Step 5). Playback conforms to `RemoteCommandHandler` as a forwarder only.
- **Sentence segmentation** → `SentenceSegmenting` (Step 1); playback reads counts via `PlaybackContentSource`.
- **Model load & voice selection** → `ModelLoading` + `VoiceSelection` (Step 6); playback only reads `isModelReady`.
- **Content ingestion / share-URL handling** → `TextIngesting` (Step 7).

## Test manifest
- `sentenceIndexBySkipping(20, forward: true)` accumulates `characterCount(ofSentence:)` until `≥ 20*13`, then clamps at `sentenceCount-1`. [off-device]
- `sentenceIndexBySkipping(20, forward: false)` is symmetric and clamps at `0`. [off-device]
- `play()` is a no-op when `!isModelReady` or `sentenceCount == 0` (no scheduler/pipeline calls, no state event). [off-device]
- Resume path (`isPaused == true`) resumes scheduler + emits `.playing` and does **not** call `store.reset()`; fresh path clears the store and calls `scheduler.start(from: currentSentenceIndex)` + `pipeline.start(from:)`. [off-device]
- pause → play rebuilds playback continuity via the injected clock hook (resume emits `.playing`; the elapsed/anchor recompute lives in the clock, not the graph). [off-device]
- Seek-while-paused sets `isPaused = false` and does **not** auto-start (no `scheduler.start`) since `wasPlaying == false`. [off-device]
- Out-of-range `seekToSentence` (negative and `≥ sentenceCount`) is a no-op. [off-device]
- `stop()` resets index/progress and emits `.stopped`, but the FakeAudioGraph records that `stop()`/teardown is **never** invoked (only `scheduler`/player-node stop). [off-device]
- `speed` setter drives the injected graph's `setRate` (asserts `timePitch.rate`), persists to `UserDefaults`, and emits `onSpeedChanged` exactly once. [off-device]
- `scheduler.onFinished` → flips `isPlaying`/`isPaused` false and emits `.finished` exactly once. [off-device]
- Across `play`/`pause`/`stop`/`seek`, FakeAudioGraph asserts `AudioGraphControlling` exposes no reachable `stop()` and the engine is never torn down (never-stop-engine guard, REFACTOR_PLAN §8). [off-device]
- `graph.start()` throwing on `play()` leaves `isPlaying == false`, `isPaused == false`, and emits no `.playing`. [off-device]
- `RemoteCommandHandler` forwarders (`remotePlay` etc.) hop `@MainActor` and invoke the matching transport method once. [device-only]

