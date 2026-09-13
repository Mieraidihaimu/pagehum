# SentenceAudioStore

## Purpose
Owns the per-index generated-audio cache and the skipped-sentence set — the single seam through which the generation writer and the playback/scheduler reader exchange `SentenceAudio` by sentence position, with atomic reset and forward eviction.

## Protocol
```swift
// Already declared in Audio/GaplessSentenceScheduler.swift:4-11 — DO NOT redeclare.
// Case order is ready/pending/skipped (not the plan's pending/ready/skipped).
enum SentenceAudioState {
    case ready(SentenceAudio)   // generated and ready to schedule
    case pending                // not generated yet — scheduler must wait for notifyAvailable()
    case skipped                // generation failed or intentionally skipped — advance past it
}

@MainActor
protocol SentenceAudioStore: AnyObject {
    func audioState(at index: Int) -> SentenceAudioState
    func put(_ audio: SentenceAudio, at index: Int)
    func markSkipped(_ index: Int)
    func evict(before index: Int)
    func reset()
}

// The scheduler's existing read seam (GaplessSentenceScheduler.swift:18-21) is UNCHANGED.
// ReaderModel's conformance (ReaderModel.swift:895-903) becomes a thin adapter that
// forwards audioState(at:) to store.audioState(at:) and sentenceCount to sentences.count.
@MainActor
protocol SentenceAudioProvider: AnyObject {
    var sentenceCount: Int { get }
    func audioState(at index: Int) -> SentenceAudioState
}
```

## Inputs
- `SentenceAudio` values with an `Int` index, pushed by the writer (`put`) — today the pipeline loop at `ReaderModel.swift:695` (`self.audioCache[genIndex] = audio`).
- Skip signals with an `Int` index (`markSkipped`) — today `ReaderModel.swift:697` (`self.skippedSentences.insert(genIndex)`).
- The audible cursor index for forward eviction (`evict(before:)`) — today the loop in `handleSentenceStarted` at `ReaderModel.swift:724`.
- Lifecycle reset signal (`reset()`) — no argument.
- `@MainActor` requirement: all methods are main-actor-isolated; the backing `audioCache: [Int: SentenceAudio]` (L103) and `skippedSentences: Set<Int>` (L104) are `@MainActor` state per CLAUDE.md and must only be touched on the main actor. The concrete store is a `class` (`AnyObject`) so the scheduler can hold it via the existing `unowned` provider reference (`GaplessSentenceScheduler.swift:48`).

## Outputs
- `audioState(at:)` returns a `SentenceAudioState` synchronously: `.ready(SentenceAudio)` if `put` for that index and not yet evicted; `.skipped` if `markSkipped` was called; otherwise `.pending` (unknown index). This is the exact three-way branch at `ReaderModel.swift:899-901`.
- No callbacks, no `AsyncStream`, no `@Published`. The store is a passive queryable container; the scheduler is separately poked via its own `notifyAvailable()` (`GaplessSentenceScheduler.swift:117`) by the writer after a `put`/`markSkipped` — that notification is NOT this unit's responsibility (see Non-goals).

## Invariants
1. **Cache and skipped set are always cleared together, atomically.** Today enforced by the paired statement `audioCache = [:]; skippedSentences = []` repeated at six sites: `selectedVoice.didSet` (L87), `prepareText` (L278), `seekToSentence` (L324), `play()` fresh path (L469), `stop()` (L507), and implicitly the pipeline reset. `reset()` replaces every one — a single call must empty both collections in one main-actor hop so a reader can never observe a half-cleared state (CLAUDE.md: "Always clear both together"). Pins the rule in CLAUDE.md Key Invariants and REFACTOR_PLAN §8.2.
2. **`audioState(at:)` precedence is ready → skipped → pending.** A `put` index reports `.ready` even if `markSkipped` was also called for it; only if not ready is `skipped` consulted; unknown is `.pending`. This mirrors the ordering at `ReaderModel.swift:899-901` (cache check before skipped check) and must be preserved verbatim.
3. **`evict(before index:)` removes only strictly-lower ready entries; the skipped set is not touched.** Matches `handleSentenceStarted` at L724 (`for key in audioCache.keys where key < index`). Entries at `>= index` (including the audible one the player still holds) are retained. Eviction is idempotent and never affects `skippedSentences` (the current code only prunes `audioCache`).
4. **`put` is last-write-wins for a given index** — re-putting overwrites, consistent with dictionary assignment at L695. `put` does not clear a prior `markSkipped` for the same index at the storage level, but by invariant 2 the state resolves to `.ready` regardless.
5. **Purely synchronous, clock-free, no I/O.** No disk, no MLX, no `Task`, no timers — fully off-device testable (REFACTOR_PLAN §4 matrix: off-device **full**, risk **low**).

## Failure modes
- **Query for an index never written / already evicted → `.pending`** (not an error, not a crash). This is correct behavior the scheduler depends on to keep waiting via `notifyAvailable()`. PIN.
- **Negative or out-of-`sentences.count` index passed to `audioState`/`put`/`evict`** → today a raw dictionary tolerates any `Int` key; the store must likewise not crash — `put`/`markSkipped` store the key, `audioState` returns `.pending` for unknown, `evict(before:)` with a small/negative bound is a no-op. PIN (no bounds check exists today; bounds are the caller's/`SentenceAudioProvider.sentenceCount` reader's concern).
- **CURRENT QUIRK — skipped set grows unbounded and is never evicted.** `evict(before:)` prunes only `audioCache` (L724); `skippedSentences` accumulates for the whole document until `reset()`. The spec says **PIN** this: skipped indices are cheap `Int`s and downstream logic relies on a skip staying `.skipped` after its buffer would have been evicted. Do not add skipped-set eviction.
- **CURRENT QUIRK — a stale `.skipped` survives a re-`put` only via precedence, not deletion.** Because storage keeps both, `markSkipped(2)` then `put(_,at:2)` yields `.ready` (invariant 2) but the index remains in the skipped set until `reset()`. PIN — no observable defect given the precedence rule.
- **Cross-actor access** would corrupt the collections; prevented by `@MainActor` isolation. Not a runtime failure mode once the protocol is honored.

## Non-goals
- **Does NOT generate audio** — synthesis (MLX/Kokoro, disk cache) is `SentenceAudioSynthesizer` (Step 8, `generateSentenceAudio` L785-830).
- **Does NOT run the lookahead producer loop or decide what/when to generate** — that is `GenerationPipeline` (Step 9, `startPipeline` L666-706), which calls `put`/`markSkipped`.
- **Does NOT notify or drive the scheduler** — `scheduler.notifyAvailable()` (L701) stays a `GenerationPipeline` responsibility; the store emits no events.
- **Does NOT schedule buffers, track the audible head, or emit `onSentenceStarted`/`onFinished`** — that is `GaplessSentenceScheduler` (existing) / `PlaybackControlling` (Step 10). The store is only the read/write surface behind `audioState(at:)`.
- **Does NOT own the sentence array, `currentSentenceIndex`, or `sentences.count`** — `sentenceCount` on the `SentenceAudioProvider` adapter reads `ReaderModel.sentences.count` (L896); the store knows nothing about sentence text.
- **Does NOT decide WHEN to reset** (voice change, new content, seek, stop) — callers in Steps 7/9/10 invoke `reset()`; the store only performs the atomic clear.

## Test manifest
Maps 1:1 to REFACTOR_PLAN §6 Step 2(d). All cases are **[off-device]** (pure main-actor state, no MLX/disk); a canned short-silence `SentenceAudio` (silent `AVAudioPCMBuffer` + fixed `[WordTiming]`) is used as the fixture.
- `put` then `audioState(at:)` returns `.ready` with the same `SentenceAudio`. [off-device]
- `markSkipped(i)` then `audioState(at: i)` returns `.skipped`. [off-device]
- Unknown / never-written index returns `.pending`. [off-device]
- `evict(before: k)` drops all ready entries with index `< k` and retains entries `>= k` (including `k`). [off-device]
- `evict(before:)` leaves `skippedSentences` untouched (skipped index below the bound still reports `.skipped`). [off-device] — pins the current-quirk decision.
- `reset()` empties both the cache and the skipped set atomically (post-reset every prior index → `.pending`). [off-device]
- Precedence: `markSkipped(i)` then `put(_, at: i)` → `.ready` (ready wins over skipped). [off-device]

