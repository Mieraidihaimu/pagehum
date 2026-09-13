# ListeningStoring

## Purpose
Accumulate per-day listening time (speed-scaled wall clock) into a unique-per-day `ListeningRecord` via SwiftData, flushing every 30s during playback and at every pause/stop/finish boundary.

## Protocol
```swift
protocol ListeningStoring: AnyObject {
    func startSession()          // begins a wall-clock session (sets session anchor to now)
    func pauseSession()          // accumulate + flush + stop the 30s timer (end of a session)
    func flush()                 // accumulate current session into today's record and persist
    func rescale(speed: Float)   // replaces the speed.didSet L73-76 accumulator recalc
}
```
Notes on the concrete type (`DefaultListeningStore: ListeningStoring`):
- `@MainActor`-confined (all SwiftData access and timer callbacks hop `@MainActor`, matching the current `Timer.scheduledTimer` closure at ReaderModel.swift L404-411 which wraps its body in `Task { @MainActor ... }`).
- Constructed with an injected `ModelContext?` provider (late-injected, may be nil), an injected clock (`() -> Date`, defaults to `Date.init`), and an injected speed source (`() -> Float`) OR the current speed pushed via `rescale`/session calls. Prefer an injected `now` closure so tests can drive elapsed deterministically.

## Inputs
- `modelContext: ModelContext?` — injected after init from `Pagehum.swift` (ReaderModel.swift L58 `var modelContext: ModelContext?`). May be nil before wiring; `flush()` is a no-op when nil (mirrors L388 `guard ... let ctx = modelContext else { return }`).
- Current playback `speed: Float` — read at accumulation time to scale wall-clock seconds (ReaderModel.swift L383 `Date().timeIntervalSince(start) * Double(speed)`). In the god-object this is `ReaderModel.speed`; post-extraction it is pushed in via `rescale(speed:)` and used by session accumulation (the unit holds its own speed copy, not a per-tick read of `ReaderModel.speed`).
- A `now()` clock for the wall-clock anchor (currently `Date()` inline at L382-384, L396, L409). `@MainActor` required for all four protocol methods.
- Implicit trigger from playback lifecycle: `startSession` on play/resume (L444-445, L472-473), `pauseSession` on pause/stop/finish (L488-490, L509-511, L740-742).

## Outputs
- Persisted `ListeningRecord` rows in the injected `ModelContext` (side effect on SwiftData store) — one row per unique `dateString` (`ListeningRecord.swift` L6 `@Attribute(.unique) var dateString`), with `secondsListened` incremented in place on same-day flushes (L394) or a new record inserted (L396).
- No `@Published` output. The unit publishes nothing back to the root; its only observable result is the SwiftData rows. (There is no callback in the current design — listening totals are read separately by the stats/settings surface via its own fetch.)

## Invariants
1. Accumulated seconds are **speed-scaled wall-clock**: `elapsed = now() - sessionStart` multiplied by the speed active during that span, not real seconds (ReaderModel.swift L383 `listeningAccumulator += Date().timeIntervalSince(start) * Double(speed)`).
2. **One `ListeningRecord` per calendar day**, keyed by `dateString = "yyyy-MM-dd"` (en_US_POSIX) — enforced by `@Attribute(.unique) var dateString` (ListeningRecord.swift L6, L16-21) and the fetch-then-increment-else-insert branch (L389-397). Two same-day flushes MUST NOT create two rows.
3. **Accumulate resets the session anchor**: `accumulateListeningTime` folds the live span into `listeningAccumulator` then sets `listeningSessionStart = nil` (L382-384), so no span is double-counted. The 30s timer re-arms the anchor to `now()` after flushing (L409).
4. **Flush zeroes the accumulator** after persist: `listeningAccumulator = 0` (L399), so the next flush starts from zero.
5. **30s periodic flush cadence** while `isPlaying`: the repeating timer fires at `withTimeInterval: 30` and only acts when playback is live (L404-406). `startSession`/`startListeningSaveTimer` first calls `stopListeningSaveTimer()` to guarantee a single live timer (L403).
6. **Speed change mid-session recalibrates the accumulator, not just the anchor**: when speed changes during playback, the elapsed-so-far span is folded in at the *old* speed and the anchor reset (`speed.didSet` L73-76: `listeningAccumulator += Date().timeIntervalSince(start) * Double(oldValue); listeningSessionStart = Date()`). `rescale(speed:)` pins exactly this behavior so seconds before the change are counted at the old rate and seconds after at the new rate.
7. **flush() is a no-op guard** when `listeningAccumulator <= 0` OR `modelContext == nil` (L388), so a nil-context (pre-wiring) or an empty session never touches SwiftData.
8. `flush()` runs on `@MainActor` and only synchronous SwiftData calls — it does NOT touch MLX/audio and never blocks on `DispatchQueue.global`; the MLX-on-GCD invariant is irrelevant here but must not be violated by adding any inference to this path.

## Failure modes
- **`ctx.save()` errors are swallowed** via `try?` (L398) and the fetch uses `try?` (L393). A failed save silently drops the accumulated seconds (accumulator is still zeroed at L399). Decision: **PIN** — preserve `try?` swallow; document that a save failure loses that flush's seconds. (Matches the plan's general "ctx.save() swallowing errors via try?" quirk note, section 5.5.)
- **nil `modelContext`**: `flush()` no-ops (L388) but the accumulator is **not** zeroed in that branch, so seconds survive until a context is injected. Decision: **PIN**.
- **Timer fires but `isPlaying == false`**: the 30s closure early-returns without accumulating (L406). If playback stopped between flushes, the tail span is captured instead by the explicit `pauseSession`/`flush` at the stop/pause/finish sites (L488-490, L509-511, L740-742), not by the timer. Decision: **PIN**.
- **Speed change while paused**: `speed.didSet` recalc is gated on `isPlaying` (L73), so a speed change while paused does not touch the accumulator; the frozen accumulator is correct because no session is running. `rescale(speed:)` must likewise no-op its recalc branch when there is no live session. Decision: **PIN**.
- **Clock going backward / DST**: `dateString` derives from wall-clock `Date()` at flush time (L389). A day rollover mid-session attributes the whole flushed span to the day of the flush, not split across midnight. Decision: **PIN** (known coarse-grained quirk; do not fix).

## Non-goals
- Does **not** own `speed` or apply it to audio — `AVAudioUnitTimePitch.rate` and the `speed` `@Published` belong to **PlaybackControlling** (Step 10); this unit only receives speed via `rescale`/session calls.
- Does **not** own the word-highlight `bufferStartTime` recalc — that is the other half of `speed.didSet` (L69-72) and belongs to **WordHighlightClock** (Step 3). `listeningSessionStart`/`listeningAccumulator` are distinct from `bufferStartTime`/`pauseElapsed`.
- Does **not** persist per-article resume position or `PlaylistItem` status — that is the sibling **ProgressStoring** (Step 4a: `saveActiveProgress`, `insertActiveItem`, `currentPlaylistItemID`).
- Does **not** decide when playback starts/stops; it only reacts to `startSession`/`pauseSession` calls emitted by **PlaybackControlling**.
- Does **not** update now-playing / lock-screen metadata (the `updateNowPlayingInfo()` also in `speed.didSet` L77) — that is **NowPlayingController** (Step 5).

## Test manifest
(In-memory `ModelContainer` — `ModelConfiguration(isStoredInMemoryOnly: true)` for `ListeningRecord`; injected `now` clock.)
- Two same-day sessions flushed → exactly **one** `ListeningRecord` (unique `dateString`), `secondsListened` summed. [off-device]
- `secondsListened == elapsed * speed` within tolerance for a single session at speed 1.0. [off-device]
- Speed-scaled: session at speed 2.0 for 10 wall-seconds → `secondsListened ≈ 20`. [off-device]
- `rescale(speed:)` mid-session: 5s at 1.0 then 5s at 2.0 → accumulator ≈ 15 (old-rate span folded at old speed before the switch, pins L73-76). [off-device]
- `flush()` with nil `modelContext` → no row inserted, no crash (pins L388). [off-device]
- `flush()` with `listeningAccumulator <= 0` → no row inserted (pins L388). [off-device]
- After `flush()`, accumulator is zeroed (a second immediate flush inserts/increments nothing). [off-device]
- `pauseSession()` then a later `startSession()` starts a fresh anchor (no carry of the paused gap into the next span). [off-device]
- 30s timer semantics: simulate timer fire while `isPlaying` → accumulates + flushes + re-anchors; while not playing → no-op (pins L404-411). [off-device]
- `startSession()` twice does not leave two live timers (pins `stopListeningSaveTimer()` at L403). [off-device]

