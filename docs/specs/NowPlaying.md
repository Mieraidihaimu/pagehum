# NowPlayingController + RemoteCommandHandler

## Purpose
Own the MediaPlayer lock-screen / Control-Center surface: publish now-playing metadata from a caller-built snapshot, route remote transport commands back to playback via callbacks, and centralize the idle-timer toggle. It is the only unit that touches `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`, and `UIApplication.shared.isIdleTimerDisabled`.

## Protocol
```swift
struct NowPlayingSnapshot {
    let title: String
    let isPlaying: Bool
    let rate: Double
    let sentenceIndex: Int
    let sentenceCount: Int
}

@MainActor protocol RemoteCommandHandler: AnyObject {
    func remotePlay()
    func remotePause()
    func remoteTogglePlayPause()
    func remoteSkipForward()
    func remoteSkipBackward()
}

@MainActor protocol NowPlayingController: AnyObject {
    func activate(handler: RemoteCommandHandler)
    func update(_ snapshot: NowPlayingSnapshot)
    func clear()
    func setIdleTimerDisabled(_ disabled: Bool)
}
```

## Inputs
- `handler: RemoteCommandHandler` via `activate(handler:)` — held **weakly** (implemented by `PlaybackControlling`, the composition root's transport unit). Registers the five `MPRemoteCommand` targets exactly once (mirrors `setupRemoteTransportControls()`, ReaderModel.swift L557-591).
- `NowPlayingSnapshot` via `update(_:)` — a value type the caller assembles from root state; the unit performs **no** reads of `content`, `isPlaying`, `speed`, `currentSentenceIndex`, or `sentences.count` itself. Fields map to the current inline reads at L595 (`title` ← `content?.title ?? "Pagehum"`), L597 (`rate` ← `isPlaying ? Double(speed) : 0.0`, so the caller passes `0.0` when paused), L601 (`sentenceIndex` ← `currentSentenceIndex`), L600/L602 (`sentenceCount` ← `sentences.count`).
- `Bool` via `setIdleTimerDisabled(_:)` — the funnel replacing the six scattered `UIApplication.shared.isIdleTimerDisabled` writes (L424 true; L434, L461, L485, L501, L737 false).
- `@MainActor`-confined: the protocol is `@MainActor`; all `MP*`/`UIKit` mutation happens on the main actor. Each remote-command closure already hops `Task { @MainActor in ... }` (L562, L568, L574, L581, L587) and must continue to.

## Outputs
- Remote-command **callbacks** out through `RemoteCommandHandler`: `playCommand → remotePlay()` (today `self?.play()`, L562), `pauseCommand → remotePause()` (L568), `togglePlayPauseCommand → remoteTogglePlayPause()` (L574), `skipForwardCommand → remoteSkipForward()` (L581), `skipBackwardCommand → remoteSkipBackward()` (L587). Each handler returns `.success` to the command center.
- Side effect only (no return value) on `update`/`clear`: writes/nils `MPNowPlayingInfoCenter.default().nowPlayingInfo` (L604 / L513) and toggles the idle timer. This unit publishes nothing as a `@Published` field; metadata flows *in* as a snapshot, commands flow *out* as callbacks — breaking the former remote↔playback cycle.

## Invariants
1. Now-playing metadata is built **only** from the injected `NowPlayingSnapshot`; the unit never reads `ReaderModel` state. (Replaces the five inline model reads in `updateNowPlayingInfo`, L595/L597/L600-602.)
2. `MPNowPlayingInfoPropertyPlaybackDuration` uses `Double(max(snapshot.sentenceCount, 1))` — duration is never 0. (Pins L600/L602 `max(sentences.count, 1)`.)
3. `MPNowPlayingInfoPropertyElapsedPlaybackTime` is `Double(snapshot.sentenceIndex)` and duration is a sentence count, not seconds — progress is expressed in sentence units. (Pins L601-602; this is intentional, carried verbatim.)
4. `MPMediaItemPropertyArtist` is always the literal `"Pagehum"` and `MPNowPlayingInfoPropertyDefaultPlaybackRate` is always `1.0`. (Pins L596, L598.)
5. Remote commands are registered exactly once via `activate(handler:)`; every command target returns `.success` and dispatches on `@MainActor`. (Pins L560-590.)
6. `skipForwardCommand.preferredIntervals` and `skipBackwardCommand.preferredIntervals` are both `[20]`. (Pins L579, L586.)
7. Idle-timer control is the sole responsibility of this unit via `setIdleTimerDisabled(_:)`; no sibling toggles `isIdleTimerDisabled` directly. (Consolidates L424/L434/L461/L485/L501/L737.)
8. `clear()` sets `nowPlayingInfo = nil` **and** calls `setIdleTimerDisabled(false)` — it does **not** touch the AVAudioEngine. The engine is never stopped here (respects never-stop-engine; this unit owns no audio graph). (Pins the `nowPlayingInfo = nil` tail of `stop()`, L513, plus the `isIdleTimerDisabled = false` at L501.)
9. `handler` is held weakly to avoid a retain cycle with `PlaybackControlling`; a released handler makes commands no-ops rather than crashing. (Mirrors `[weak self]` capture at L561 etc.)
10. On non-iOS platforms (`#if !os(iOS)`), `update`/`clear`/`setIdleTimerDisabled`/`activate` are inert no-ops. (Pins the `#else` stub `updateNowPlayingInfo() {}`, L660.)

## Failure modes
- **`sentenceCount == 0`** → duration coerced to `1` (Invariant 2); no divide/empty-artwork crash. PIN.
- **`title == ""` or empty snapshot title** → the caller substitutes `"Pagehum"` before building the snapshot (mapping of L595's `?? "Pagehum"` moves to the caller); the unit sets whatever title string it is given. The `?? "Pagehum"` fallback lives at the snapshot-construction site, tested as "nil/empty title → shows Pagehum". PIN.
- **Paused state** → caller passes `rate: 0.0` (from L597's `isPlaying ? Double(speed) : 0.0`); lock screen shows a paused transport. PIN.
- **CURRENT QUIRK — no artwork, no real duration:** the surface reports sentence index/count instead of elapsed/total seconds, so the lock-screen scrubber is coarse and non-time-accurate. Spec says **PIN** (preserve current behavior); a seconds-accurate timeline is out of scope for this refactor.
- **CURRENT QUIRK — command targets are additive and never removed:** re-calling `activate` would stack duplicate `addTarget` handlers (the god-object called `setupRemoteTransportControls()` once from `init`, L167). Spec says **FIX defensively**: `activate` must be idempotent (register once; guard or `removeTarget` before re-adding) so the unit can be reconstructed without duplicate fan-out.
- **Released handler** (weak ref niled) → commands return `.success` but perform no playback action. PIN (matches `[weak self]` behavior where `self` is gone).

## Non-goals
- Does **not** run or read the transport state machine — `play()/pause()/stop()/togglePlayback()/skipForward()/skipBackward()` and the `isPlaying`/`isPaused`/`speed` truth belong to **PlaybackControlling** (Step 10); this unit only forwards command intents to it via `RemoteCommandHandler`.
- Does **not** own or mutate the AVAudioEngine, `playerNode`, or `AVAudioSession` — that is **AudioGraphControlling** / **PlaybackControlling**. `clear()` must never call `audioEngine.stop()`.
- Does **not** persist progress or compute `currentSentenceIndex`/`progress` — that is **ProgressStoring** (Step 4). The old inline `updateNowPlayingInfo()` call inside `saveProgressNow()` (L376) is removed; the progress-save caller instead builds a fresh snapshot and calls `update(_:)`.
- Does **not** own `content`, `sentences`, or `speed` — those stay as shared root state fed by **TextIngesting** / **PlaybackControlling**; this unit receives their projection as a snapshot.
- Does **not** manage listening-time accumulation (that is **ListeningStoring**, Step 4) even though those calls sit beside the idle-timer toggles in `pause()`/`stop()`/`handlePlaybackFinished()`.

## Test manifest
- `update` with `isPlaying=true, rate=1.5` → `MPNowPlayingInfoPropertyPlaybackRate == 1.5`. [device-only] (simulator)
- `update` with paused snapshot (`isPlaying=false, rate=0.0`) → playback rate `0.0`. [device-only]
- `update` with `sentenceCount == 0` → `MPNowPlayingInfoPropertyPlaybackDuration == 1`. [device-only]
- `update` with nil/empty title (snapshot built via the `?? "Pagehum"` mapping) → title `"Pagehum"`. [device-only]
- simulate `playCommand` fire → `handler.remotePlay()` invoked exactly once; command returns `.success`. [off-device] (fake `RemoteCommandHandler`)
- skip commands register `preferredIntervals == [20]` for both forward and backward. [off-device]
- `clear()` → `MPNowPlayingInfoCenter.default().nowPlayingInfo == nil` and idle timer set false. [device-only]
- each remote command hops `@MainActor` (handler method observed on the main actor). [off-device]
- `setIdleTimerDisabled(true)`/`(false)` routes to the injectable idle-timer sink (fake) — asserts the six call-site consolidation. [off-device]
- `activate` called twice does not double-register (single `remotePlay()` per one `playCommand` fire). [off-device]

