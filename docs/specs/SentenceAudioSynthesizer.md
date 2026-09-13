# SentenceAudioSynthesizer

## Purpose
The single MLX/Kokoro synthesis boundary: turn one sentence of text into a decoded `SentenceAudio` (disk-cache-first), returning `nil` to signal "skip". It is the only type in the app that touches `KokoroTTS`/`MLXArray`; every unit above it is regenerable off-device against a fake.

## Protocol
```swift
// Collaborator-facing seam (GenerationPipeline / Step 9 depends ONLY on this).
// `Language` is the KokoroSwift enum (.enUS / .enGB); `SentenceAudio` and `WordTiming`
// are the app's MLX-free DTOs (ReaderModel.swift L28-34, Models/WordTiming.swift L10-14).
protocol SentenceAudioSynthesizer: Sendable {
    func synthesize(text: String,
                    voiceKey: String,
                    language: Language,
                    format: AVAudioFormat) async -> SentenceAudio?
}

// Disposable concrete impl — captures the loaded model by value (not from ReaderModel).
struct DefaultSentenceAudioSynthesizer: SentenceAudioSynthesizer {
    init(engine: KokoroTTS?,                 // from LoadedModel (Step 6), was kokoroTTSEngine L39
         voices: [String: MLXArray],         // from LoadedModel (Step 6), was voices L43
         diskCache: AudioDiskCache = .shared) // temp-dir-injectable via AudioDiskCache(directory:) L35
}
```

## Inputs
- `text: String` — the (already ≤400-char, `SentenceSegmenting`-trimmed) sentence to synthesize.
- `voiceKey: String` — the fully-resolved Kokoro voice key **including the `.npy` suffix** (caller builds `selectedVoice + ".npy"`, L671). This unit does not append it.
- `language: Language` — resolved KokoroSwift enum (`.enUS`/`.enGB`); caller derives it (L672). This unit does not derive it.
- `format: AVAudioFormat` — target PCM format for the returned buffer: Float32, 24 kHz, mono, non-interleaved (built from `KokoroTTS.Constants.samplingRate`, L123-125).
- Injected at construction (was captured inline from the god-object at L786-787 `let engine = kokoroTTSEngine; let voicesCopy = voices`): `engine: KokoroTTS?`, `voices: [String: MLXArray]` (both handed over from `LoadedModel`, Step 6), and an `AudioDiskCache` (defaults to `.shared`; tests inject a temp dir).
- **Not `@MainActor`.** The type is `Sendable` and does all work off the main actor; callers may invoke `synthesize` from any actor/Task.

## Outputs
- Single `async` return value `SentenceAudio?`:
  - `.some(SentenceAudio)` — `buffer` (decoded PCM in `format`, `frameLength == audio.count`, L803-807), `tokens: [WordTiming]?` (`nil` when no timings), `leadingSilence` (0 for fresh synth; non-zero only on AAC cache hits whose priming couldn't be trimmed — set by `AudioDiskCache`, L107).
  - `nil` — the skip signal (miss + un-synthesizable, or any failure). No throws, no callbacks, no `AsyncStream`.
- Side effect: on a successful fresh synth, a **fire-and-forget** disk write (`AudioDiskCache.store`, L821) — never awaited, never blocks the return.

## Invariants
1. **MLX + disk I/O run on `DispatchQueue.global(qos: .userInitiated)` via `withCheckedContinuation`, NEVER `Task.detached` / the cooperative pool** — pins L789-790 (`generateSentenceAudio`) and the CLAUDE.md "Never use `Task.detached` for MLX/Kokoro work" rule (MLX's internal `DispatchQueue.sync` deadlocks the cooperative pool).
2. **Disk-cache-first**: `diskCache.load(text:voiceKey:)` is consulted before any Kokoro call; a hit `resume`s immediately and skips inference entirely (L791-794).
3. **Never throws.** Every path `resume(returning:)`s; the Kokoro `try engine.generateAudio(...)` is wrapped in `do/catch` and the catch resumes `nil` (L824-826). `nil` is the only failure channel.
4. **Generation is always `speed: 1.0`** (L800). Playback speed is applied later via `AVAudioUnitTimePitch.rate` (Step 10), not here.
5. **`MToken → WordTiming` is mapped exactly once, here** — the only Kokoro/MLX token boundary in the app (L817, `WordTiming(text:$0.text, start:$0.start_ts, end:$0.end_ts)`). Empty timings collapse to `tokens: nil` (L818, `timings.isEmpty ? nil : timings`).
6. **Store is fire-and-forget after a successful synth** and never gates the return (L820-821); a store failure leaves the sentence uncached but still returns the audio.
7. **`engine`/`voices` are captured by value at construction** (post-extraction from `LoadedModel`), replacing the inline closure captures at L786-787 — the synthesizer never reaches into `ReaderModel`'s `kokoroTTSEngine`/`voices` fields.
8. **Output buffer conforms to the injected `format`**: `frameCount = AVAudioFrameCount(audio.count)`, `buffer.frameLength = frameCount`, samples `memcpy`'d into channel 0 (L803-814).
9. **`Sendable`** — safe to call from `GenerationPipeline`'s background `Task` across actor boundaries (it owns no `@MainActor` state).

## Failure modes
- disk hit → returns cached `SentenceAudio` (may carry non-zero `leadingSilence`); no MLX. **PIN** (design contract of `AudioDiskCache`).
- corrupt / missing / schema-mismatched `.json` sidecar → `AudioDiskCache.load` returns `nil` (a miss), synth falls through to Kokoro. **PIN** (AudioDiskCache "nil on ANY imperfection" contract, AudioDiskCache.swift L8-11, L74-98).
- `engine == nil` (model not yet loaded) → `nil` before any MLX call (L796). **PIN.**
- `voices[voiceKey] == nil` (unknown/mistyped voice) → `nil` before inference (L797). **PIN.**
- `engine.generateAudio` returns empty audio → `nil` (L801). **PIN.**
- `AVAudioPCMBuffer` allocation fails → `nil` (L804-805). **PIN.**
- Kokoro throws (e.g. `tooManyTokens`) → caught, `print("Kokoro error: …")`, `nil` (L824-826). **PIN behavior**; note the current quirk that the error is only `print`ed (no structured telemetry) — spec **PINS** this (do not add error surfacing here; error visibility is out of scope).
- **Known quirk (PIN): `nil` conflates transient vs permanent failure.** "engine not loaded" and "this sentence is un-synthesizable" both return `nil`; the pipeline (Step 9) treats every `nil` as `markSkipped`. This spec preserves the single-`nil` contract — distinguishing the two is explicitly **not** introduced here.

## Non-goals
- Does **not** own the lookahead/throttle loop, the `≤lookaheadCount` window, `isGenerating`, or `generationTask` — **GenerationPipeline** (Step 9, L666-706).
- Does **not** write `audioCache` / `skippedSentences` or decide skip-persistence — **SentenceAudioStore** (Step 2); the pipeline calls `markSkipped` on a `nil` return.
- Does **not** load the model or own `kokoroTTSEngine`/`voices` lifecycle — **ModelLoading** (Step 6); it receives them via `LoadedModel`.
- Does **not** own disk-cache encoding, LRU eviction, schema versioning, or key hashing — **AudioDiskCache** (exists, Services/AudioDiskCache.swift).
- Does **not** derive `voiceKey` (the `.npy` suffix, L671) or `Language` (`selectedVoice.first == "a" ? .enUS : .enGB`, L672) — **GenerationPipeline** (Step 9) resolves and passes both.
- Does **not** apply playback speed — **PlaybackControlling** (`timePitch`, Step 10); synth is always `speed: 1.0`.

## Test manifest
(Maps 1:1 to Step 8(d). Off-device tests use `FakeSynthesizer` and drive `AudioDiskCache` directly, which is already temp-dir-injectable.)
- `FakeSynthesizer` conforms to `SentenceAudioSynthesizer`, returning canned `SentenceAudio` (short silent `AVAudioPCMBuffer` + fixed `[WordTiming]`) or `nil` for the skip path — the harness enabler for `GenerationPipeline` off-device. **[off-device]**
- `AudioDiskCache` round-trip: `store` then `load` returns a buffer whose `frameLength` and `tokens` match the input. **[off-device]**
- corrupt / missing `.json` sidecar → `load` returns `nil` (a miss). **[off-device]**
- real `synthesize` (disk miss) returns a non-empty 24 kHz mono Float32 buffer with `frameLength == audio.count`. **[device-only]**
- `engine == nil` → `nil` (never invokes MLX). **[off-device]**
- unknown `voiceKey` (`voices[voiceKey] == nil`, real engine) → `nil` before inference. **[device-only]**
- empty audio from Kokoro → `nil`. **[device-only]**
- `AVAudioPCMBuffer` alloc failure → `nil`. **[device-only]**
- Kokoro `tooManyTokens` throw → caught → `nil`. **[device-only]**

