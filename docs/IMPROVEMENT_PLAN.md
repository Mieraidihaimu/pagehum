# Pagehum — Improvement Plan

Status snapshot: the app is architecturally sound (clean TTS pipeline, correct MLX-deadlock
handling, thoughtful speed/highlight sync). The items below are refinements, prioritized by
impact. This document also contains the **detailed design for A2 (gapless playback)**, which is
being implemented now, plus the unit-test specification for its new component.

---

## 1. Backlog overview

### Audio playback performance

| ID | Item | Where | Impact | Status |
|----|------|-------|--------|--------|
| A1 | **Persist generated audio to disk**, keyed by `hash(voice + sentence)`. The `AudioCacheManager` directory is never written to today — audio lives only in the in-memory `audioCache`, wiped on every play/stop/seek. Makes re-reads, skip-back, and offline instant. | `AudioCacheManager`, `generateSentenceAudio` | ★★★ | backlog |
| **A2** | **Gapless playback.** `playLoop` schedules one buffer, then `await`s its completion before scheduling the next → a main-actor round-trip gap between every sentence. Keep 2–3 buffers scheduled on the node so they play back-to-back. | `ReaderModel` → new `GaplessSentenceScheduler` | ★★★ (audible) | **in progress** |
| A3 | **Non-destructive seek.** `seekToSentence` clears the whole cache; with A1 in place, keep entries and just re-point the cursor so skip-back is instant. | `seekToSentence` | ★★ | backlog (needs A1) |
| A4 | **Faster cold start.** Generate a short leading chunk of sentence 0 first, or pre-warm sentence 0 in `prepareText` before the user taps play. | `startPipeline` / `prepareText` | ★★ | backlog |
| A5 | **Replace poll loops with signalling.** `playLoop` polled the cache every 50 ms and the generator gated on `sleep(200 ms)`. A2 removes the playback poll via an event (`notifyAvailable`); the generator gate can follow. | pipeline | ★ | partly done by A2 |

### UX

- **Hacker News article previews** — implemented 2026-10-21. Stories have a separate preview action with loading, retry, browser and HN discussion links; selection stays independent of the current reader and playback.
- **iCloud sync** — deferred; sync the library and resume position between Mac and iPhone. See the [implementation checklist](#4-icloud-sync--deferred-implementation-checklist).
- **Sleep timer** ("stop after 15/30/60 min or end of article") — top missing feature for a reading/bedtime TTS app.
- **Auto-play on resume** — `PlaylistView.reloadItem` loads content but leaves it paused.
- **"Continue listening" card on Home** — surface the most recent in-progress item.
- **Deep-link routing inconsistency** — a shared Safari URL always opens the plain `ReaderView`
  (`Pagehum.swift` app-level `navigationDestination`), while the same URL loaded in-app opens
  `WebReaderView`. Route shared URLs through `source.webURL` like the rest of the app.
- **First-play feedback** — the play button flips to "pause" instantly though audio may be seconds
  away; gate a "Preparing…" state on `audioState(at: currentSentenceIndex)`.
- **Keyboard-on-launch** — Home auto-focuses the URL field on every appear.
- **Share extension is URL-only** — could also accept shared text and PDFs.

### UI

- **Minimized bubble pauses on tap** — tapping the minimized control to expand it also calls
  `viewModel.pause()` (`PlaybackControlsView.swift:156`). Expanding shouldn't stop audio.
- **Word-highlight recompute cost** — `SentenceView.highlightedSentence` re-splits the sentence and
  rebuilds a `Text` concatenation via `reduce` every 40 ms; precompute words once / use
  `AttributedString`.
- **Asymmetric transport layout** — a `Color.clear.frame(width: 56)` spacer fakes centering; use a
  proper 3-zone `HStack`.
- **Accessibility** — active-word cue is color+underline only; transport buttons lack
  `accessibilityLabel`; control chrome ignores Dynamic Type.

---

## 2. A2 — Gapless playback (detailed design)

### 2.1 Problem

`ReaderModel.playLoop()` (pre-A2) played strictly one sentence at a time:

```
schedule(buffer[i]) → await completionHandler → advance i → schedule(buffer[i+1]) …
```

`AVAudioPlayerNode` finishes buffer *i*, fires its completion handler on an internal queue, that
hops to `@MainActor`, the loop body runs, and only then is buffer *i+1* scheduled. The node is idle
for that whole round-trip → an audible gap between sentences. It also coupled scheduling, cache
polling, word-highlight timing, and progress persistence into one 65-line loop that could not be
tested without a real `AVAudioEngine` + MLX on a device.

### 2.2 Approach

`AVAudioPlayerNode` plays *consecutively scheduled* buffers with **no gap**. So keep up to
`maxInFlight` (default 3) buffers scheduled on the node at all times. Each buffer's completion
handler means "the head sentence just finished; the next one is already playing" — use it to (a)
advance the audible cursor and (b) top the queue back up.

This logic is extracted into a small, dependency-injected, main-thread component
`GaplessSentenceScheduler` that has **no** direct knowledge of `AVAudioEngine`, MLX, the generation
pipeline, word highlighting, or persistence.

### 2.3 Responsibilities

| Component | Owns / does | Explicitly does NOT do |
|-----------|-------------|------------------------|
| `GaplessSentenceScheduler` | Decide scheduling order; keep ≤`maxInFlight` buffers queued for gaplessness; track the audible index; emit `onSentenceStarted` / `onFinished`; handle `skipped` / `pending` / end-of-content. | Generate audio; own the engine/session; do word highlighting; persist progress; evict the cache. |
| `AudioBufferPlayer` (protocol) + `AVAudioPlayerNodeAdapter` | Thin, mockable wrapper over `AVAudioPlayerNode.scheduleBuffer/play/pause/stop`. Guarantees completion is delivered on the main thread. | Any scheduling policy. |
| `SentenceAudioProvider` (protocol) | Answer "what is the audio state of sentence *i*?" (`ready` / `pending` / `skipped`) and "how many sentences?". Implemented by `ReaderModel`'s cache. | Decide playback order. |
| `ReaderModel` | Wire the three together; own engine/session/pipeline; react to callbacks (highlight, index, progress, listening time, now-playing). | Manual buffer scheduling (moved to scheduler). |

### 2.4 Dependencies (injected)

```
GaplessSentenceScheduler
 ├─ player:   AudioBufferPlayer        (mock in tests, AVAudioPlayerNodeAdapter in prod)
 ├─ provider: SentenceAudioProvider    (stub in tests, ReaderModel in prod)
 ├─ maxInFlight: Int = 3
 ├─ onSentenceStarted: (Int, SentenceAudio) -> Void   // SentenceAudio.tokens drives highlighting
 └─ onFinished: () -> Void
```

`onSentenceStarted` passes `SentenceAudio` (an app-module type the scheduler already handles via
`.ready`) rather than `[MToken]`, so the scheduler needs **no** `import KokoroSwift`/`MLX` and stays
compilable/testable off-device. The model reads `audio.tokens` in the callback.

Both protocols and the scheduler are `@MainActor` (the provider impl is `@MainActor`, and all
`AVAudioPlayerNode` calls already happen on main). `provider` is held `unowned` (the model owns the
scheduler → no retain cycle); the model assigns the two output closures with `[weak self]`.

### 2.5 Algorithm

State: `nextToSchedule: Int`, `inFlight: [Int]` (scheduled, not yet completed; `inFlight.first` is
audible), `announcedHead: Int?`, `isActive: Bool`, `tokensByIndex: [Int: [MToken]?]`.

- **`start(from:)`** → reset, `isActive = true`, `nextToSchedule = from`, `player.play()`,
  `refill()`, `syncAudibleHead()`.
- **`refill()`** → while active and `inFlight.count < maxInFlight` and `nextToSchedule < count`:
  - `.skipped` → `nextToSchedule += 1` (advance past it)
  - `.pending` → `return` (cannot schedule out of order; wait for `notifyAvailable()`)
  - `.ready(audio)` → append index to `inFlight`, store tokens, `player.schedule(buffer)` with a
    completion that calls `handleCompletion(of: idx)`, `nextToSchedule += 1`.
  - After the loop, if active and `inFlight` empty and `nextToSchedule >= count` → `finish()`.
- **`handleCompletion(of:)`** (main thread) → remove the completed index from `inFlight`, drop its
  tokens, `refill()`, `syncAudibleHead()`.
- **`syncAudibleHead()`** → if `inFlight.first` changed, record it and fire
  `onSentenceStarted(head, tokens)`. This is the single choke point that announces a sentence the
  moment it becomes audible — including the very first one and any that were `pending` at start.
- **`notifyAvailable()`** → called by the generation pipeline whenever a sentence is cached or
  skipped; just `refill()` + `syncAudibleHead()` so a previously-`pending` head can start.
- **`pause()` / `resume()`** → forward to the player; scheduled buffers and their completions are
  retained across pause, so no re-scheduling is needed.
- **`stop()`** → `isActive = false`, `player.stop()` (flushes scheduled buffers), reset state.

### 2.6 Why timing stays correct

`onSentenceStarted(i)` fires when sentence *i* becomes the head — i.e. right as the node begins
playing it (for the first sentence, at `start`/first `notifyAvailable`; for the rest, inside the
previous sentence's completion). The model sets `bufferStartTime = Date()` there, so the existing
40 ms word-highlight timer stays in sync with what is actually audible. The small main-actor hop
(≈ ms) is negligible against sentence-length audio and matches the pre-A2 behavior.

### 2.7 Integration points in `ReaderModel`

- `init` — build `AVAudioPlayerNodeAdapter(playerNode)`, construct the scheduler with
  `provider: self`, assign `onSentenceStarted` → `handleSentenceStarted`, `onFinished` →
  `handlePlaybackFinished`.
- Conform `ReaderModel: SentenceAudioProvider` (`sentenceCount`, `audioState(at:)` reading
  `audioCache` / `skippedSentences`).
- `play()` — fresh start: reset cache, `startPipeline()`, `scheduler.start(from:)`. Resume path:
  `scheduler.resume()`.
- `pause()` / `stop()` / `seekToSentence()` — delegate to `scheduler.pause()/stop()`.
- `startPipeline()` — after caching or skipping a sentence, call `scheduler.notifyAvailable()`.
- **Removed:** `playLoop()`, `playbackTask`, `shouldContinue`, and the per-sentence
  `scheduleBuffer`/poll logic.

### 2.8 Behavior changes / notes

- **The 10 s "stuck sentence" timeout is dropped.** It only skipped *slow* generation, which risked
  dropping real content. It is unnecessary for correctness: `generateSentenceAudio` always either
  caches a sentence or marks it `skipped` (on `nil`/error) and calls `notifyAvailable()`, so the
  scheduler always makes progress — it never hangs on a sentence that will never arrive. If a
  visible "generation is slow" affordance is wanted later, add a model-side watchdog that calls
  `provider`-marks-skipped + `notifyAvailable()`; keep it out of the scheduler so the scheduler stays
  clock-free and deterministic for tests.
- **Docs to update:** the `ReaderModel.swift` architecture notes in `CLAUDE.md` and the
  `kokoro-tts-engine-invariants` memory reference `playLoop`/`playbackTask`; update them to describe
  the scheduler seam once A2 lands.

### 2.9 Risks & verification (device-only build)

This touches the core audio path and cannot be built/run outside Xcode on a physical device
(MLX has no simulator). After opening in Xcode, verify:

1. **Gaplessness** — play a multi-sentence article; sentence transitions have no audible gap.
2. **Word highlight** — highlighted word tracks the audio across sentence boundaries and after a
   speed change mid-playback.
3. **Pause/resume** — resumes at the same word; no double audio.
4. **Seek** — dragging the progress bar / skip ±20 s restarts cleanly at the new sentence.
5. **Skips** — an article containing a sentence that fails generation advances past it.
6. **End of content** — playback stops, progress hits 100 %, listening time is saved.
7. **Voice change mid-playback** — pipeline restarts on the new voice without a stuck state.
8. **Background + lock screen** — remote play/pause/skip still work.

---

## 3. Unit-test specification for `GaplessSentenceScheduler`

No test target exists in the Xcode project yet. When one is added
(`File ▸ New ▸ Target ▸ Unit Testing Bundle` → `PagehumTests`), implement the cases below.
The scheduler is fully testable on the main thread with two hand-written fakes and **no** device,
`AVAudioEngine`, or MLX.

### 3.1 Test doubles

```swift
// Records schedule calls and lets the test fire completions on demand (in order),
// simulating gapless back-to-back playback deterministically.
final class MockBufferPlayer: AudioBufferPlayer {
    private(set) var isPlaying = false
    private(set) var scheduledCount = 0
    private var completions: [() -> Void] = []

    func play()  { isPlaying = true }
    func pause() { isPlaying = false }
    func stop()  { isPlaying = false; completions.removeAll() }
    func schedule(_ buffer: AVAudioPCMBuffer, onComplete: @escaping () -> Void) {
        scheduledCount += 1
        completions.append(onComplete)
    }
    /// Simulate the head buffer finishing playback.
    func completeHead() { guard !completions.isEmpty else { return }; completions.removeFirst()() }
    var inFlightOnNode: Int { completions.count }
}

// Serves a fixed per-index state; the test can flip pending→ready then notify.
final class StubAudioProvider: SentenceAudioProvider {
    var states: [SentenceAudioState]              // index-aligned
    var sentenceCount: Int { states.count }
    init(_ states: [SentenceAudioState]) { self.states = states }
    func audioState(at index: Int) -> SentenceAudioState { states[index] }
}
```

A tiny helper builds a real (silent) `AVAudioPCMBuffer` for `.ready` — buffers are plain data
containers and construct fine off-device:

```swift
func makeBuffer() -> AVAudioPCMBuffer {
    let fmt = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    return AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 1)!
}
func ready(_ tokens: [MToken]? = nil) -> SentenceAudioState { .ready(SentenceAudio(buffer: makeBuffer(), tokens: tokens)) }
```

### 3.2 Cases (given / when / then)

1. **Keeps `maxInFlight` buffers queued (the gapless guarantee)**
   Given 5 ready sentences, `maxInFlight = 3`; when `start(from: 0)`; then `player.scheduledCount == 3`
   and `inFlightOnNode == 3` **before** any completion fires. (This is the core regression guard —
   pre-A2 it would be 1.)

2. **Announces the first sentence on start**
   Given ready sentences; when `start(from: 0)`; then `onSentenceStarted` fired once with index 0.

3. **Advances the head on completion and tops up the queue**
   Given 5 ready, started; when `completeHead()`; then `onSentenceStarted` fires with index 1, and a
   4th buffer gets scheduled (`scheduledCount == 4`, `inFlightOnNode == 3`).

4. **Starts from a non-zero index (resume/seek)**
   When `start(from: 2)`; then first `onSentenceStarted` index is 2 and sentence 0/1 are never
   scheduled.

5. **Skips `.skipped` sentences without scheduling them**
   Given `[ready, skipped, ready]`; when `start(from: 0)` then `completeHead()`; then indices 0 and 2
   are announced, index 1 is never scheduled/announced.

6. **Waits on `.pending`, resumes on `notifyAvailable()`**
   Given `[pending, ready]`; when `start(from: 0)`; then nothing scheduled and no announcement. When
   provider flips index 0 to `ready` and `notifyAvailable()`; then index 0 is scheduled and announced.

7. **Pending head after a completion**
   Given `[ready, pending]`, started; when `completeHead()`; then no new schedule and no announcement.
   When index 1 → ready + `notifyAvailable()`; then index 1 scheduled and announced.

8. **Fires `onFinished` after the last sentence completes**
   Given 2 ready, started; when `completeHead()` twice; then `onFinished` fired exactly once and no
   further `onSentenceStarted`.

9. **Empty content finishes immediately**
   Given 0 sentences; when `start(from: 0)`; then `onFinished` fired once, `scheduledCount == 0`.

10. **All-skipped content finishes without playing**
    Given `[skipped, skipped]`; when `start(from: 0)`; then `onFinished` fired, nothing scheduled.

11. **`stop()` halts scheduling and suppresses late completions**
    Given started with buffers in flight; when `stop()` then `completeHead()`; then no
    `onSentenceStarted`/`onFinished` fire after stop (late completions are ignored via `isActive`).

12. **Audio/tokens are passed through**
    Given `ready(tokensA)` at index 0; when started; then `onSentenceStarted` delivers a
    `SentenceAudio` whose `tokens == tokensA`.

13. **`onSentenceStarted` fires once per sentence (no duplicates)**
    Drive a full 3-sentence run; assert the announced index sequence is exactly `[0,1,2]`.

---

## 4. iCloud sync — deferred implementation checklist

Saved: 2026-09-10. Status: planned for later; implementation has not started.

Goal: **same library, resume where you left off** on Mac and iPhone signed into the same Apple
Account. Use SwiftData with a shared private CloudKit container. Devices should converge after
changes have synced; immediate handoff and a fixed sync latency are not promised. Keep the app
usable offline.

### First-version scope

| Data | Decision |
|---|---|
| Library items, source URLs, titles, extracted text | Sync |
| Resume position, completion status, library deletions | Sync |
| Active playback, audio engine, generated audio cache | Keep local |
| Up next order, voice/speed preferences, listening statistics | Defer syncing |
| Original PDF files, webpage cookies and browsing state | Outside the first version; extracted text remains available |

### Phase 1 — Configure iCloud and settle the schema

- [ ] Enable CloudKit and required remote-notification capabilities for the Mac and iPhone builds; configure both to use the same private container under the same developer team.
- [ ] Configure `ModelContainer` explicitly for that container and verify signing/provisioning on both physical devices.
- [ ] Audit `PlaylistItem` for CloudKit compatibility, including required property defaults, stable application-level IDs, and content revision identity for saved playback offsets.
- [ ] Keep `ListeningRecord` in a local-only store for v1. Its current `@Attribute(.unique)` constraint cannot be used in a CloudKit-backed schema; plan the store split and migration before enabling sync.
- [ ] Define how independently imported copies of the same normalized URL are reconciled after sync. Local duplicate checks alone do not cover simultaneous offline imports; avoid silently losing progress or different saved text revisions.

### Phase 2 — Preserve existing data and sync the library

- [ ] Implement and test migration from the existing local library, preserving extracted text, progress, dates, completion status, and local listening statistics.
- [ ] Verify initial upload and downloading the library onto a second device, including existing data on both devices.
- [ ] Refresh library views as remote additions, edits, and deletions arrive.
- [ ] Define delete-versus-edit behavior and handle deletion of an open article without crashes or accidental resurrection.
- [ ] Retain durable local data when iCloud is unavailable. Do not turn a sync failure into an unnoticed in-memory-only session.
- [ ] Check large extracted articles against CloudKit storage limits and choose an appropriate payload representation before production rollout.

### Phase 3 — Make resume position reliable

- [ ] Separate a deliberate playback/seek update from merely viewing an article. `saveProgressNow()` currently updates `lastPlayed` when an item is opened, which must not overwrite newer remote progress.
- [ ] Define a coherent progress checkpoint containing the content revision, text offset, completion state, and conflict-ordering metadata.
- [ ] Implement deterministic conflict resolution for the most recent deliberate listening/seek action, including timestamp ties and clock skew. Do not simply choose the greatest offset: restarting and seeking backward are valid actions.
- [ ] Save checkpoints during listening and on pause, seek, completion, and app backgrounding, with bounded write frequency.
- [ ] Adopt synced progress when reopening/resuming an item; never jump the position underneath active local playback or start playback remotely.

### Phase 4 — Test and release

- [ ] Add tests for conflict resolution, URL reconciliation, content revision changes, and migration of populated stores.
- [ ] Test Mac → iPhone and iPhone → Mac for imports, deletes, completion, restart, backward seek, and resume.
- [ ] Test concurrent edits, offline changes followed by reconnect, app termination/relaunch, and a fresh installation restoring an existing library.
- [ ] Test unavailable iCloud, sign-out/account changes, quota/network failures, and recovery without data loss or account data mixing.
- [ ] Show actionable sync problems and explain that updates may be delayed; only display successful-sync information when supported by observed sync events.
- [ ] Verify the development schema, promote it to production, and repeat cross-device checks using distribution builds. Plan schema changes carefully because production CloudKit schemas are additive.

Exit condition: both devices converge on the same library and a consistent saved resume position
after syncing, existing local data survives migration, and remote updates never disrupt active
listening.

### Later work

- [ ] Persist and sync Up next order; the current `ListeningQueue` is an in-memory session object.
- [ ] Decide which preferences should follow the user across devices.
- [ ] Redesign listening statistics around mergeable sessions/events before syncing totals, so concurrent listening does not overwrite another device's contribution.

References: [Apple's SwiftData sync guide](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)
and [CloudKit synchronization behavior](https://developer.apple.com/documentation/technotes/tn3163-understanding-the-synchronization-of-nspersistentcloudkitcontainer).
