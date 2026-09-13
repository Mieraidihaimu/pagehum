# SentenceSegmenting

## Purpose
Pure, stateless split of body text into trimmed, non-empty sentence chunks each ≤ `maxSentenceLength` (default 400) characters, so downstream Kokoro synthesis never hits `tooManyTokens`. Replaces the god-object statics `splitIntoSentences`/`splitLongSentence`/`maxSentenceLength` (ReaderModel.swift L834–L890).

## Protocol
```swift
protocol SentenceSegmenting {
    var maxSentenceLength: Int { get }
    func splitIntoSentences(_ text: String) -> [String]
}

struct DefaultSentenceSegmenter: SentenceSegmenting {
    let maxSentenceLength: Int
    init(maxSentenceLength: Int = 400)
    func splitIntoSentences(_ text: String) -> [String]
}
```
`splitLongSentence` stays a private implementation detail of the concrete type (currently ReaderModel.swift L857) — it is NOT part of the protocol surface. Collaborators depend only on `splitIntoSentences(_:)` and the `maxSentenceLength` getter.

## Inputs
- `text: String` — the raw body text to segment. The single argument to `splitIntoSentences`.
- `maxSentenceLength: Int` — injected once at init (default 400), the single source of truth for the cap. Replaces the re-hardcoded `private static let maxSentenceLength = 400` (L834); callers must no longer re-declare `400` inline.
- No `@MainActor` requirement. Pure Foundation/`NLTokenizer` (unit: `.sentence`) computation, safe to call from any thread/actor. No dependency injection beyond the length cap; no clock, no shared state.

## Outputs
- Return value only: `[String]` — ordered, whitespace/newline-trimmed, non-empty chunks (empty strings filtered at L842 `if !s.isEmpty`; per-chunk trim at L841/L865/L870). No callbacks, no events, no `@Published` writes, no `AsyncStream`. Output order preserves source order (append-only accumulation, L844/L846).

## Invariants
1. Sentence boundaries come from `NLTokenizer(unit: .sentence)` enumerated over `text.startIndex..<text.endIndex` (L837–L840); the unit must not use a hand-rolled `.` scanner.
2. Every emitted chunk is `.trimmingCharacters(in: .whitespacesAndNewlines)` and non-empty (L841–L842); pure-whitespace input yields `[]`.
3. A tokenizer chunk with `count <= maxSentenceLength` is kept verbatim; `count > maxSentenceLength` is delegated to `splitLongSentence` (L843–L847). Boundary is inclusive: exactly `maxSentenceLength` is kept, `maxSentenceLength + 1` is split.
4. `splitLongSentence` first splits at clause delimiters `[",", ";", ":", "—", "–"]`, but only when the accumulated `current.count >= 80` (the clause gate, L864). Short clauses are not broken.
5. If clause-splitting produced `<= 1` chunk and the sentence still exceeds `maxSentenceLength`, fall back to word-boundary packing on `split(separator: " ")` (L874–L887); a word is never broken mid-word (L879 guards on `!current.isEmpty`).
6. `splitLongSentence` never returns empty: `chunks.isEmpty ? [sentence] : chunks` (L889).
7. NLTokenizer-empty fallback: if the tokenizer yields nothing but trimmed input is non-empty, return `[text]` when `text.count <= maxSentenceLength` else `splitLongSentence(text)` (L851–L853). Note this fallback uses the raw `text`, not a trimmed copy.
8. Stateless & referentially transparent: identical input → identical output; safe to call concurrently (supports the Step 7 "serialize in-flight extractions" invariant without itself needing serialization).
9. Generation downstream always synthesizes at `speed: 1.0` and relies on this cap to bound token count (CLAUDE.md Key Invariants; ReaderModel.swift L800) — the cap must never be raised silently past what Kokoro tolerates.

## Failure modes
- Pure-whitespace / empty input → `[]` (L842 filter + L851 guard both fail to append). PIN.
- A single "word" with no spaces and no clause delimiters that exceeds `maxSentenceLength` (e.g. a 500-char URL or token run) is returned **oversize as one chunk**: clause split yields one chunk (no delimiters), the word-split loop cannot break mid-word, so `chunks == [sentence]` at 500 chars (trace of L874–L889). This can still trip Kokoro's `tooManyTokens` at synthesis time. **Decision: PIN** (characterized as the "500-char single token returned oversize" case) — the segmenter does not hard-truncate; recovery is the synthesizer returning `nil` → skip path (Step 8/9), not this unit's concern.
- Fallback-path input (tokenizer returns empty) is split from the **untrimmed** `text` (L851–L852), so leading/trailing whitespace can ride along into the single returned chunk in that specific branch, unlike the normal path which trims. **Decision: PIN** (matches current behavior; downstream synth trims again).
- Clause delimiters inside a run shorter than 80 chars are ignored (gate at L864), so a sentence of many short comma clauses may exceed the cap before the first split fires, then falls through to word-splitting. PIN.

## Non-goals
- Does NOT extract or fetch text, normalize URLs, run WKWebView/PDFKit, or build `ReadingContent` — that is `TextExtracting`/`ContentLoader` (Step 7). `prepareText` does **not** move here; it lives in ContentLoader and merely *calls* `segmenter.splitIntoSentences`.
- Does NOT clear or touch `audioCache`/`skippedSentences` — that seam is `SentenceAudioStore` (Step 2). Segmenting has zero shared state.
- Does NOT own `sentences` (`@Published` on the root) or write it; it only returns the array the applier assigns (Step 7 `ReaderStateApplier`).
- Does NOT tokenize into words or produce `WordTiming`/`MToken` data — word-level timing belongs to the synthesizer + `WordHighlightClock` (Steps 8/3).
- Does NOT decide synthesis language/voice or per-sentence audio state.

## Test manifest
Maps 1:1 to Step 6 §1(d). All [off-device] — pure Foundation/NaturalLanguage, runnable in plain XCTest on a Mac (no device, no MLX).
- [off-device] empty string and whitespace-only string → `[]`.
- [off-device] a 400-char clause is kept as one chunk; a 401-char clause is split (inclusive boundary, invariant 3).
- [off-device] clause split honors the ≥80-char gate: delimiters before 80 chars accumulated do not break (invariant 4).
- [off-device] comma-free / delimiter-free text > 400 chars with spaces → word-boundary split, no mid-word break (invariant 5).
- [off-device] 500-char single token (no spaces/delimiters) → returned oversize as one chunk (PINNED quirk).
- [off-device] multi-sentence input preserves source order (invariant 2/append order).
- [off-device] NLTokenizer-empty fallback → `[text]` for short input (invariant 7).

