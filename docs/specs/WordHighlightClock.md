# WordHighlightClock

## Purpose
Derive the currently-spoken token index and text from a speed-scaled wall-clock anchor over a sentence's `[WordTiming]`, emitting only on transitions. It owns the timing anchor and the tick loop; it does not own the `@Published` fields the UI binds to.

## Protocol
```swift
protocol WordClockDateProvider {
    func now() -> Date
}

protocol HighlightTicker: AnyObject {
    func start(interval: TimeInterval, _ onTick: @escaping () -> Void)
    func stop()
}

@MainActor
protocol WordHighlightClock: AnyObject {
    /// Fired only when the resolved token changes. `tokenIndex == -1`, `wordText == ""`
    /// means "no word highlighted" (leading silence, reset, or before first token).
    var onWordChanged: ((_ tokenIndex: Int, _ wordText: String) -> Void)? { get set }

    /// Begin timing a newly-audible sentence. Resets the highlight to (-1, "") and starts the
    /// ticker. `leadingSilence` is folded into the anchor so the index stays -1 until it elapses.
    func begin(tokens: [WordTiming]?, leadingSilence: TimeInterval)

    func pause()
    func resume()
    func setSpeed(_ newSpeed: Float)
    func reset()
}
```

## Inputs
- `dateProvider: WordClockDateProvider` (injected). Production: a `SystemDateProvider` returning `Date()`. Off-device: `FixedClock` (advanceable). Every wall-clock read that is `Date()` today (`ReaderModel.swift` L70, L71, L442, L479, L720, L765) routes through `dateProvider.now()`.
- `ticker: HighlightTicker` (injected). Production: a `TimerTicker` wrapping `Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true)` (mirrors `startWordTimer` L748-753). Off-device: `ManualTicker` whose `fire()` synchronously invokes the stored `onTick`.
- `interval: TimeInterval` = `0.04` (40 ms), the tick period passed to `ticker.start` (pins L750 `withTimeInterval: 0.04`).
- `begin(tokens:leadingSilence:)` — `tokens: [WordTiming]?` (the sentence's `audio.tokens`, `WordTiming { text, start, end }` from `Models/WordTiming.swift`) and `leadingSilence: TimeInterval` (`SentenceAudio.leadingSilence`, L33), supplied by playback in `handleSentenceStarted` (L712-720).
- `setSpeed(_:)` — a `Float` speed copy pushed on every speed change; the clock holds its own copy and never reads `ReaderModel.speed` per tick.
- All members are `@MainActor`; `onWordChanged` is invoked on the main actor.

## Outputs
- `onWordChanged(tokenIndex, wordText)` callback — the ONLY way this unit surfaces state. The composition root wires it to the shared `@Published currentTokenIndex` (L51) and `currentWordText` (L50). The clock writes neither field directly.
- No return values, no `AsyncStream`, no persistence. `pause`/`resume`/`setSpeed`/`begin`/`reset` mutate only clock-internal state (`bufferStartTime`, `pauseElapsed`, `currentTokens`, internal `speed`).

## Invariants
1. Elapsed position is computed as `elapsed = (now() - anchor) * speed` in original 1.0x audio seconds, using the clock's own speed copy (pins `updateWordHighlight` L765; removes the per-tick read of `ReaderModel.speed`).
2. Token resolution scans all tokens in order and selects the LAST index `i` whose `token.start != nil` and `elapsed >= token.start`; tokens with `start == nil` are skipped (pins L768-773). The `>=` boundary and "last match wins" are load-bearing and PINNED.
3. Emission is de-duplicated: `onWordChanged` fires only when the resolved index differs from the last emitted index (pins `if newIndex != currentTokenIndex` L775). `wordText` is set only when `0 <= newIndex < tokens.count` (pins L777-778).
4. `leadingSilence` is folded into the anchor as `anchor = now() + leadingSilence` (pins `bufferStartTime = Date().addingTimeInterval(audio.leadingSilence)` L720). While `elapsed` is negative no token matches, so the index stays -1.
5. `begin` resets the highlight to `(-1, "")`, clears `pauseElapsed` to 0, stores `tokens`, sets the anchor per invariant 4, and (re)starts the ticker (pins L714-720, L726; `startWordTimer` self-invalidates first, L749).
6. `pause` freezes progress by capturing `pauseElapsed = now() - anchor` and stops the ticker (pins L478-480, L487). `resume` re-anchors as `anchor = now() - pauseElapsed` and restarts the ticker (pins L442-443). No ticks occur while paused.
7. `setSpeed` recalibrates the anchor to preserve elapsed audio-seconds across a rate change WHILE RUNNING: `elapsedAudio = (now() - anchor) * oldSpeed; anchor = now() - elapsedAudio / newSpeed` (pins the anchor-recalc half of `speed.didSet`, L69-72 only). The listening-accumulator recalc (L73-76) is NOT this unit's concern.
8. Backward movement of the token index is permitted (invariant 2 recomputes from scratch each tick), so a `setSpeed` that lowers the rate can emit a lower index than previously (pins the plan's "backward index allowed after speed-down").
9. `reset` clears `currentTokens`, `pauseElapsed`, and the anchor, stops the ticker, and emits `(-1, "")` exactly once (via invariant 3 dedup against the last emitted index). This is the single funnel replacing the scattered `currentTokenIndex = -1; currentWordText = ""` writes at seek (L329-330), stop (L504-505), and `handlePlaybackFinished` (L734), plus the `stopWordTimer` calls at L323, L452, L487, L508, L739.
10. The clock never calls `audioEngine.stop()` or touches the audio graph/scheduler; the ticker is the only external side-effect source (respects never-stop-engine; that graph lives in PlaybackControlling).

## Failure modes
- `begin(tokens: nil, ...)` or `begin(tokens: [], ...)`: `updateWordHighlight`'s guard (`!tokens.isEmpty`, L761) makes every tick a no-op; the highlight stays at the `(-1, "")` from `begin`. PIN.
- A tick with no anchor set (before any `begin`, or after `reset`): guard `let startTime = bufferStartTime` (L762) short-circuits; no emission. PIN (reinforced by `reset` clearing the anchor so a stray queued tick cannot resolve a stale token).
- Token with `start == nil`: silently skipped (L769 `guard ... else { continue }`); a sentence whose tokens all have nil starts never advances past -1. PIN.
- CURRENT QUIRK — speed change while PAUSED does not rescale `pauseElapsed`: today `speed.didSet` recalibrates only `if isPlaying` (L69), so changing speed while paused leaves the frozen offset in old-rate wall-seconds and `resume` drifts. This spec PINS the running-only recalc (so characterization tests stay green against the god-object). Rescaling `pauseElapsed` on `setSpeed` while paused is a documented FIX-LATER, not applied here.
- CURRENT QUIRK — `stop()` (L494-515) resets `currentTokenIndex`/`currentWordText` but leaves `bufferStartTime`/`pauseElapsed`/`currentTokens` populated; only `wordTimer` stopping prevents a stray highlight. The extracted `reset()` FIXES this by clearing all internal timing state, closing the stale-token window. FIX (behavior-compatible: no emission difference, since the ticker is already stopped).
- Timing precision: the 40 ms production ticker plus `Task { @MainActor }` hop (L751) means transitions land within one tick of the true boundary. Off-device tests remove this nondeterminism entirely via `ManualTicker` + `FixedClock`. PIN (device-only jitter, untested).

## Non-goals
- Does NOT own or write `@Published currentTokenIndex` / `currentWordText` — the composition root owns them and feeds them from `onWordChanged`. (anti-leak fence: "zero direct writers remain" is the Step 3 done-criterion.)
- Does NOT own `progress`, `currentSentenceIndex`, or decide when a sentence becomes audible — PlaybackControlling / GaplessSentenceScheduler own that and drive `begin(...)` (from `handleSentenceStarted`).
- Does NOT own the listening-time accumulator or its speed rescale (L73-76) — that is ListeningStoring (Step 4, `rescale(speed:)`).
- Does NOT persist progress or call `saveProgressNow` — ProgressStoring (Step 4).
- Does NOT touch `AVAudioEngine`, `playerNode`, `timePitch`, or the audio session — AudioGraphControlling / PlaybackControlling (Step 10). `setSpeed` here recalibrates the anchor only; `timePitch.rate` (L63) is set elsewhere.
- Does NOT read `ReaderModel.speed`, `sentences`, or any model field per tick — speed arrives via `setSpeed`, tokens via `begin`.

## Test manifest
Maps 1:1 to Step 3(d), all driven by `FixedClock: WordClockDateProvider` + `ManualTicker: HighlightTicker`:
- `begin` then advance clock across token boundaries emits `(0, "Hello")` then `(1, "world")` in order. [off-device]
- De-dup: repeated ticks within the same token's window emit `onWordChanged` exactly once per transition. [off-device]
- `setSpeed(2.0)` mid-run preserves elapsed audio-seconds (resolved index unchanged immediately after the rate change; subsequent advance scales by 2x). [off-device]
- Pause/resume continuity: `pause`, advance the clock ~10s while paused (no emissions), `resume` continues from the frozen offset — not from the advanced wall time. [off-device]
- `leadingSilence` keeps the index at -1 while `elapsed` is negative, then advances to token 0 once it turns non-negative. [off-device]
- `reset()` emits `(-1, "")` exactly once and stops the ticker; a subsequent forced tick produces no emission. [off-device]
- `nil` tokens (and tokens with `start == nil`) are skipped: ticks over such input never emit a non-negative index. [off-device]
- Backward index allowed after speed-down: `setSpeed` to a lower rate can emit a lower token index than previously emitted. [off-device]

