# ModelLoading

## Purpose
Load the Kokoro TTS engine and voice tensors off the main actor (GCD, never the cooperative pool) and hand them back as an immutable `LoadedModel`; derive display voice names and pick the initial voice deterministically, without writing any `ReaderModel` fields as a side effect.

## Protocol
```swift
// Immutable result of a successful load — the only value that crosses the seam.
struct LoadedModel {
    let engine: KokoroTTS
    let voices: [String: MLXArray]
    let voiceNames: [String]
}

// Errors thrown instead of force-unwrapping bundle URLs (fold-in fix for L175-176).
enum ModelLoadingError: Error {
    case missingModelResource   // kokoro-v1_0.safetensors absent from bundle
    case missingVoicesResource  // voices.npz absent from bundle
    case noVoicesLoaded         // NpyzReader produced an empty voice map
}

protocol ModelLoading: AnyObject {
    var isModelLoaded: Bool { get }
    func load() async throws -> LoadedModel   // GCD + withCheckedContinuation; idempotent
}

// Pure, MLX-free string helpers — fully off-device testable.
enum VoiceNameDeriver {
    static func displayNames(from voiceKeys: [String]) -> [String]
    static func defaultVoice(available: [String], stored: String) -> String
}

// Owns voiceNames + selectedVoice; set from a LoadedModel without a pipeline restart.
@MainActor protocol VoiceSelection: AnyObject {
    var voiceNames: [String] { get }
    var selectedVoice: String { get }
    func apply(_ model: LoadedModel)                 // seed names + initial voice from load result
    func select(_ voice: String)                     // user-initiated change
    var onVoiceChanged: ((_ voice: String) -> Void)? { get set }  // fires only on genuine change
}
```

## Inputs
- `Bundle.main` resources: `kokoro-v1_0` / `safetensors` (model, L175) and `voices` / `npz` (voice tensors, L176). Injectable as a `Bundle` (default `.main`) so tests can supply a fixture-less bundle to exercise the throw paths.
- `UserDefaults` (default `.standard`) key `"selectedVoice"` (read L190) — the persisted voice preference; injectable for `VoiceSelection` tests.
- `NpyzReader.read(fileFromPath:)` for the voice `.npz` (L181) — device-adjacent, exercised only in the real `load()`.
- `KokoroTTS(modelPath:)` initializer (L180) — MLX; device-only.
- For `VoiceNameDeriver`: `voiceKeys: [String]` (the `voices` dictionary keys) and a `stored: String` preference — no injected dependencies, pure functions.
- `VoiceSelection.apply(_:)` takes a `LoadedModel`; must run on `@MainActor` (writes `voiceNames`/`selectedVoice` which back `@Published` UI state on the root).

## Outputs
- `load()` returns a `LoadedModel` (engine, voices, voiceNames) or throws `ModelLoadingError`. It does **not** write `kokoroTTSEngine`, `voices`, `voiceNames`, `selectedVoice`, or `isModelLoaded` on the root (replaces the four foreign-field writes at L186-188, L192/194, L196).
- `isModelLoaded` is a read-only flag on the `ModelLoading` unit, flipped true only after a load that yields a non-empty voice map (fold-in fix; see Invariants 2 and Failure modes).
- `VoiceNameDeriver.displayNames` → `[String]` sorted ascending; `VoiceNameDeriver.defaultVoice` → a single `String`.
- `VoiceSelection` publishes selection changes via the `onVoiceChanged` callback — the composition root wires it to `selectedVoice` and (when playing) a pipeline restart. State flows out as a callback, never by the unit poking `@Published`.
- `LoadedModel.engine` / `.voices` flow onward to `SentenceAudioSynthesizer` (Step 8), not read as shared props by generation.

## Invariants
1. Model + voice load runs on `DispatchQueue.global(qos: .userInitiated)` inside `withCheckedContinuation`, never `Task.detached` or the cooperative pool — MLX uses internal `DispatchQueue.sync` that deadlocks the cooperative thread pool (ReaderModel.swift `loadModel` L178-184; CLAUDE.md "Model loading" / "Never use Task.detached for MLX/Kokoro work").
2. `isModelLoaded` becomes true **only when `voices` is non-empty** (fold-in fix, replacing the unconditional `isModelLoaded = true` at L196). This closes the latent loaded-but-no-voices bug where an empty `NpyzReader` result (`?? [:]`, L181) still gated `play()` open at L422.
3. `load()` is idempotent: a second call after success returns the already-loaded `LoadedModel` (or re-derives it) without re-dispatching MLX work; `isModelLoaded` never regresses to false.
4. Display-name derivation pins the current transform: `key.split(separator: ".")[0]`, mapped over `voices.keys`, `sorted(by: <)` (L188). E.g. `"af_heart.npy" → "af_heart"`, `"af.v2.npy" → "af"`.
5. Default-voice selection order is preserved exactly (L190-195): honor `stored` if present in the derived names; else the first name with prefix `"af"`; else the first name; else `""`.
6. `VoiceSelection.apply(_:)` seeds the initial voice **without** triggering the pipeline-restart side effect that `selectedVoice.didSet` performs (L84-88). This removes the fragile startup ordering contract that today only works because the didSet early-returns while `!isPlaying` (L84; REFACTOR_PLAN §8.4).
7. Persistence of the chosen voice to `UserDefaults` key `"selectedVoice"` (today L83) is retained, performed by `VoiceSelection`, not by any `didSet` on a shared field.

## Failure modes
- Missing model bundle URL → today force-unwraps and crashes (`Bundle.main.url(...)!`, L175). Spec says **FIX**: throw `ModelLoadingError.missingModelResource`; `isModelLoaded` stays false, no partial state written.
- Missing voices bundle URL → today force-unwraps and crashes (L176). Spec says **FIX**: throw `ModelLoadingError.missingVoicesResource`.
- `NpyzReader.read` returns `nil`/empty → today coalesces to `[:]` (L181) and still sets `isModelLoaded = true` (latent bug). Spec says **FIX**: treat empty voices as failure (`throw .noVoicesLoaded` or leave `isModelLoaded == false`); `play()` gate stays closed.
- Empty/whitespace derived names with an empty `stored` → `defaultVoice` returns `""` (pins L194 `?? ""`); downstream synthesis will produce no voice match and skip. Preserve.
- `stored` preference no longer present among loaded voices → falls through to af-prefix/first/empty (L191-194). Preserve.

## Non-goals
- Does **not** own audio synthesis or any MLX `generateAudio` call — that is `SentenceAudioSynthesizer` (Step 8), which captures `engine`/`voices` from the `LoadedModel`.
- Does **not** own the pipeline restart on voice change — the composition root reacts to `onVoiceChanged` and drives `GenerationPipeline` (Step 9) + `SentenceAudioStore.reset()` (Step 2); this unit never touches `audioCache`/`skippedSentences`/`generationTask`.
- Does **not** own transport gating logic — `play()`'s `isModelLoaded` guard (L422) lives in `PlaybackControlling` (Step 10), which reads the flag via `PlaybackContentSource.isModelReady`.
- Does **not** own the audio engine, session, or scheduler (Step 10 / `AudioGraphControlling`).
- Does **not** persist article/progress state (`ProgressStoring`, Step 4).

## Test manifest
- `VoiceNameDeriver.displayNames(["af_heart.npy","bm_george.npy"]) == ["af_heart","bm_george"]` [off-device]
- `VoiceNameDeriver.displayNames(["af.v2.npy"]) == ["af"]` (pins `split(".")[0]`) [off-device]
- `VoiceNameDeriver.displayNames` is sorted ascending regardless of input order [off-device]
- `defaultVoice(available:, stored:)` honors a valid stored preference [off-device]
- `defaultVoice` af-prefix preference when stored absent [off-device]
- `defaultVoice` first-name fallback when no af-prefix present [off-device]
- `defaultVoice` empty-array → `""` fallback [off-device]
- Stub `ModelLoading` returning a fixed `LoadedModel` → `isModelLoaded` flips true and the `play()` gate opens [off-device]
- `isModelLoaded` stays false when the stub load yields an empty voice map (fold-in fix) [off-device]
- `load()` throws `missingModelResource` / `missingVoicesResource` against a bundle without the fixtures (fold-in fix) [off-device]
- `VoiceSelection.apply(_:)` seeds `voiceNames`/`selectedVoice` and does **not** fire `onVoiceChanged` for the initial seed (no startup pipeline restart) [off-device]
- `VoiceSelection.select(_:)` fires `onVoiceChanged` once only on a genuine change and persists to `UserDefaults` [off-device]
- Real `load()` returns a non-empty engine + voice map on `DispatchQueue.global`, `isModelLoaded` true [device-only]

