# GenerationPipeline

## Purpose
A single lookahead producer loop that fills the `SentenceAudioStore` with synthesized sentence audio, staying at most `lookaheadCount` sentences ahead of the playback cursor and emitting produced/generating events. It owns no audio, no cache dictionaries, and no scheduling — only the "what to generate next, and when to throttle" decision. (Extracts `startPipeline()` ReaderModel.swift L666-706.)

## Protocol
```swift
@MainActor protocol GenerationPipeline: AnyObject {
    func start(from startIndex: Int)
    func stop()
    var onProduced: ((_ index: Int) -> Void)? { get set }
    var onGeneratingChanged: ((Bool) -> Void)? { get set }
}
```

Collaborators it depends on (already specified in sibling steps — do not redefine here):
```swift
// Step 8 — the MLX boundary; Sendable, off-actor, never throws.
protocol SentenceAudioSynthesizer: Sendable {
    func synthesize(text: String, voiceKey: String, language: Language, format: AVAudioFormat) async -> SentenceAudio?
}
// Step 2 — the write seam.
enum SentenceAudioState { case pending, ready(SentenceAudio), skipped }
@MainActor protocol SentenceAudioStore: AnyObject {
    func audioState(at index: Int) -> SentenceAudioState
    func put(_ audio: SentenceAudio, at index: Int)
    func markSkipped(_ index: Int)
    func evict(before index: Int)
    func reset()
}
```

## Inputs
- `synthesizer: SentenceAudioSynthesizer` (injected; `Sendable`) — replaces the in-closure `kokoroTTSEngine`/`voices` capture at L786-787. The pipeline never sees an MLX symbol.
- `store: SentenceAudioStore` (injected; `@MainActor`, `AnyObject`) — the only place produced audio lands. Replaces the raw `audioCache`/`skippedSentences` writes at L695/L697.
- A **cursor source** for the playback position, read as a throttle bound only — the current `currentSentenceIndex` (L49). In the composition root this is supplied via the `PlaybackContentSource.currentSentenceIndex` (Step 10) or an equivalent `() -> Int` read closure. The pipeline **reads** it (L674, L683, L688); it never writes it. `@MainActor`.
- A **sentence source**: `sentences: [String]` snapshot (L98) — used for count bound (L675) and per-index text (L690). Supplied at `start(from:)` time or via the content source; must be stable for the life of one `start`/`stop` run.
- `voiceKey: String` — derived once per run as `selectedVoice + ".npy"` (L671). `selectedVoice` from root (L81).
- `language: Language` — derived once per run as `selectedVoice.first == "a" ? .enUS : .enGB` (L672). `Language` is the KokoroSwift enum passed straight to `synthesize`.
- `format: AVAudioFormat` — `audioFormat` (L124-126): `AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!` where `sampleRate = Double(KokoroTTS.Constants.samplingRate)` (L123), i.e. 24 kHz mono. Computed once as `self.audioFormat` at L670.
- `lookaheadCount: Int` — the throttle depth, default `3` (L106). Should be an init parameter (single source of truth), not re-hardcoded.
- `@MainActor`: the loop body runs on the main actor (matches the current `startPipeline` `Task` which inherits the `@MainActor` isolation of `ReaderModel`); only `synthesize` hops off-actor internally (Step 8's GCD boundary).

## Outputs
- `onProduced: ((Int) -> Void)?` — fired once per index **after** that index is written to the store (`.ready` via `put` or `.skipped` via `markSkipped`), in ascending index order. Replaces the `scheduler.notifyAvailable()` fan-out at L701 (the composition root wires `onProduced` → `scheduler.notifyAvailable()`).
- `onGeneratingChanged: ((Bool) -> Void)?` — fired when the "generating the sentence the listener is waiting on" flag changes. Replaces the direct `isGenerating` `@Published` writes at L688, L699, L704 (root wires it → `isGenerating`, which Views bind to).
- Side effect: writes into `store` via `put(_:at:)` on success (L695) and `markSkipped(_:)` on nil (L697). No return value; no other observable output.

## Invariants
1. **At most one generation run.** `start(from:)` cancels and nils the prior `generationTask` before creating a new one (L667-668: `generationTask?.cancel(); generationTask = Task {…}`). `stop()` cancels + nils it. There is never more than one live task.
2. **Bounded lookahead (≤ `lookaheadCount` ahead of cursor).** Before synthesizing index `genIndex`, the loop spins `while genIndex - cursor >= lookaheadCount && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(200)) }` (L683-685). With cursor pinned at 0 and `lookaheadCount == 3`, exactly indices 0,1,2 are produced, then it blocks at 3.
3. **Cache-hit fast path yields.** If `store.audioState(at: genIndex)` is already `.ready` (was `audioCache[genIndex] != nil` at L676), the loop advances `genIndex` and awaits `Task.yield()` before continuing (L677-679) — pins the CLAUDE.md rule "Pipeline loops must yield" to avoid starving the UI/WKWebView. No `onProduced` is emitted for a pre-existing entry (matches current L676-679, which never calls `notifyAvailable`).
4. **MLX stays on GCD, off this actor.** The pipeline calls `await synthesizer.synthesize(...)` (replacing L691); the actual `KokoroTTS.generateAudio` runs on `DispatchQueue.global(qos: .userInitiated)` via `withCheckedContinuation` inside the synthesizer (L789-790, L800). The pipeline MUST NOT wrap synthesis in `Task.detached` or move it onto the cooperative pool (CLAUDE.md: MLX deadlocks there).
5. **Generation speed is always 1.0.** The pipeline passes text/voice/language/format only; speed is applied later via `AVAudioUnitTimePitch.rate`, never at generation (`engine.generateAudio(..., speed: 1.0)` L800). The pipeline must not pass a speed.
6. **`onGeneratingChanged(true)` only when the listener is blocked.** The flag is `store.audioState(at: cursor)` is not `.ready` (current: `isGenerating = audioCache[currentSentenceIndex] == nil` L688), set immediately before each synth call; cleared (`false`) after each write (L699) and once more when the loop exits (L704). Emit only on transitions (de-dup) so the root's `@Published isGenerating` doesn't churn.
7. **Cooperative cancellation everywhere.** The outer loop condition and every inner wait check `!Task.isCancelled` (L675, L683, L686 `guard !Task.isCancelled else { break }`, L693). After cancellation the store is never written for the in-flight index.
8. **Store is the sole sink.** Success → `store.put(audio, at: genIndex)`; nil → `store.markSkipped(genIndex)` (replacing L694-698). The pipeline never touches raw dictionaries and never clears the store (`reset()`/`evict` are owned elsewhere — see Non-goals).
9. **Ascending, once-per-index production.** `genIndex` starts at the cursor (L674) and only increments (L678, L702), bounded by `sentences.count` (L675); each index is produced at most once per run.

## Failure modes
- **`synthesize` returns `nil`** (engine nil, missing voice, empty audio, buffer-alloc failure, or Kokoro `tooManyTokens`/throw — all collapse to `nil` per Step 8 L796-801, L804-806, L824-826): the pipeline calls `store.markSkipped(genIndex)` (L697), emits `onProduced(genIndex)`, and advances. Playback then skips that sentence via the scheduler's `.skipped` handling. **PIN** (this is the documented skip-past-failure contract, CLAUDE.md "Skipped sentences").
- **Busy-wait throttle.** When ahead of the cursor, the loop polls with `Task.sleep(200ms)` rather than awaiting a signal (L683-685) — up to ~200ms latency between the cursor advancing and the next synth starting. **PIN** (preserve current behavior; a signal-based wake is out of scope for this extraction).
- **`isGenerating` flicker.** Because the flag is recomputed against the cursor's cache state before each synth and cleared after each (L688, L699), it can toggle true→false repeatedly while producing lookahead beyond an already-ready cursor. **PIN the semantics**, but FIX the fan-out by emitting `onGeneratingChanged` only on value change (de-dup) so downstream `@Published` writes are minimized.
- **Empty `sentences` / cursor ≥ count.** Loop condition `genIndex < sentences.count` (L675) is immediately false → no synth calls, `onGeneratingChanged(false)` at exit (L704). Safe no-op. **PIN.**
- **`stop()` mid-synth.** Cancels the task; the currently-awaited `synthesize` completes off-actor but its result is dropped by the `guard !Task.isCancelled` after the await (L693). Store is not written; `onGeneratingChanged(false)` is emitted. **PIN.**
- **Restart / voice change.** On `selectedVoice` change mid-play the root clears the store and calls `start(from:)` again (today: L86-88 cancels task, clears cache, `startPipeline()`); the new run re-derives `voiceKey`/`language` and re-seeds from the current cursor. The pipeline itself does not detect voice changes — restart is caller-driven. **PIN.**

## Non-goals
- **Does not synthesize audio or touch MLX/Kokoro/disk.** That is `SentenceAudioSynthesizer` (Step 8), which also owns the `AudioDiskCache` read/write (L792, L821). No MLX symbol may appear in this unit.
- **Does not own or clear the cache.** `audioCache`/`skippedSentences` and their `reset()`/`evict(before:)` belong to `SentenceAudioStore` (Step 2). Eviction of already-played audio (`handleSentenceStarted` L724 → `store.evict(before:)`) is triggered by `PlaybackControlling` (Step 10), not here.
- **Does not schedule or play buffers.** Gapless scheduling, `onSentenceStarted`/`onFinished`, and the player node are `GaplessSentenceScheduler` + `PlaybackControlling` (Step 10). The pipeline only signals availability via `onProduced` (root routes it to `scheduler.notifyAvailable()`).
- **Does not advance or write the playback cursor.** `currentSentenceIndex` is owned/advanced by `PlaybackControlling`/`GaplessSentenceScheduler`; the pipeline reads it as a throttle bound only.
- **Does not derive voice display names or default-voice selection.** That is `VoiceSelection`/`VoiceNameDeriver` (Step 6); the pipeline receives a ready `voiceKey`.
- **Does not own the `@Published isGenerating` field.** It emits `onGeneratingChanged`; the composition root projects it onto the shared `@Published`.

## Test manifest
(Off-device: `FakeSynthesizer` returning canned `SentenceAudio` or `nil`, real `SentenceAudioStore`, cursor via injectable read closure/stub content source. Maps 1:1 to Step 9(d).)
- `[off-device]` cursor pinned at 0 with 5 sentences → store holds exactly `lookaheadCount` (3) entries, then the loop blocks (no 4th synth call). (Invariant 2)
- `[off-device]` advancing the cursor by one → exactly one additional synth call / store entry appears. (Invariant 2)
- `[off-device]` synthesizer returns `nil` at index 2 → `store.audioState(at:2) == .skipped` via `markSkipped(2)`, loop proceeds to index 3. (Failure: nil→skip)
- `[off-device]` store pre-populated at an index (`.ready`) → synthesizer is **not** invoked for it and the loop yields past it; no `onProduced` for that index. (Invariant 3)
- `[off-device]` `stop()` halts further synth calls and emits `onGeneratingChanged(false)`. (Invariants 1, 7)
- `[off-device]` `onProduced` fires once per produced index in ascending order (freshly synthesized and skipped indices only). (Invariant 9)
- `[off-device]` restart (`start(from:)` again) cancels the prior run and re-seeds from the new start index. (Invariant 1)
- `[off-device]` voiceKey / language derivation: `selectedVoice == "af_heart"` → `voiceKey == "af_heart.npy"`, `language == .enUS`; `selectedVoice == "bf_emma"` → `language == .enGB`. (Inputs / L671-672)

