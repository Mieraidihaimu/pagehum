# TextIngesting

## Purpose
Normalize/route a raw URL, PDF, or pasted-text request into an `IngestedDocument` (extracted `ReadingContent` + segmented `[String]` + originating `ContentSource`), and drain the share-extension inbox (`UserDefaults` app-group + `pagehum://open` deep link) into a pending URL string — without touching playback, the audio store, or SwiftData.

## Protocol
```swift
// Extraction seam (concrete default: TextExtractor, @MainActor — Services/TextExtractor.swift L9-10)
protocol TextExtracting: AnyObject {
    func extract(from source: ContentSource) async throws -> ReadingContent
}

// Share-extension inbox seam (app-group UserDefaults + deep-link parse)
protocol SharedURLInbox: AnyObject {
    func drainSharedURL() -> String?          // one-shot read+remove of UserDefaults(suiteName:)[key]
    func parseDeepLink(_ url: URL) -> String?  // returns the "url" query param, or nil
}

struct IngestedDocument {
    let content: ReadingContent   // Models/ReadingContent.swift L14-20
    let sentences: [String]
    let source: ContentSource     // Models/ReadingContent.swift L3-12
}

// Orchestrator (concrete default: ContentLoader). @MainActor: WKWebView extraction is main-actor bound.
@MainActor protocol TextIngesting: AnyObject {
    func ingest(rawURL: String) async throws -> IngestedDocument
    func ingest(pdf url: URL) async throws -> IngestedDocument
    func ingest(text: String) async throws -> IngestedDocument
    func extractForSaving(rawURL: String) async throws -> ReadingContent
    func normalizedURL(from raw: String) -> URL?
}
```

## Inputs
- A `TextExtracting` instance — default `TextExtractor()` (replaces the stored `extractor` at ReaderModel.swift L100). `@MainActor`; owns the single `WKWebView` and the Readability JS / PDFKit / plain-text branches (TextExtractor.swift L14-23). Injectable as a fake off-device.
- A `SentenceSegmenting` instance (Step 1, `DefaultSentenceSegmenter`) — used to build `IngestedDocument.sentences`, replacing the direct `Self.splitIntoSentences(text)` call at ReaderModel.swift L275. This unit does **not** own the split algorithm.
- A `SharedURLInbox` instance whose default reads `UserDefaults(suiteName: appGroupID)` under `sharedURLKey`. The suite (`UserDefaults`) must be injectable so tests can supply an isolated suite. `appGroupID = "group.com.test.mier.hello"` (L201) and `sharedURLKey = "SharedURL"` (L202) — these are a cross-target contract and must equal `ShareViewController.appGroupID`/`sharedURLKey` (ShareViewController.swift L6-7).
- Raw inputs from Views: a URL/text string, a PDF file `URL`, or an incoming deep-link `URL` (`handleOpenURL` L214-221).
- No `ModelContext` — persistence is not an input here (moved to `ProgressStoring`, Step 4).

## Outputs
- `ingest(rawURL:)` / `ingest(pdf:)` / `ingest(text:)` → `IngestedDocument` (returned value).
- `extractForSaving(rawURL:)` → `ReadingContent` (the extraction half of `saveForLater` L283-310, minus the SwiftData insert).
- `normalizedURL(from:)` → `URL?` (trim + `https://` prepend logic of `loadURL` L231-235).
- `drainSharedURL()` → `String?` (one-shot; the value `checkForSharedURL` L205-212 would have assigned to `pendingSharedURL`).
- `parseDeepLink(_:)` → `String?` (the `url` query param `handleOpenURL` L214-221 extracts).
- Thrown errors flow out for the caller/applier to map: `"Invalid URL"` (L236/L288), `"Please enter some text"` (L244), `URLError(.timedOut)` (TextExtractor L33-35), `URLError(.zeroByteResource)` with `"No readable text could be extracted from this page."` (TextExtractor L45-49), `URLError(.cannotOpenFile)` (TextExtractor L237).
- NOT outputs (owned elsewhere): the `@Published` `content`/`sentences`/`isLoading`/`errorMessage` and resume `currentSentenceIndex`/`progress` are written by a root-side `ReaderStateApplier`; `pendingSharedURL` (@Published, L203) is a root projection fed by `drainSharedURL()`/`parseDeepLink(_:)`; `store.reset()` + `pipeline.stop()` are fired by the applier via a `contentReplaced` event, never by this unit.

## Invariants
1. **Serialize in-flight extractions (NEW — FIX).** At most one `TextExtracting.extract(from:)` may execute at a time; concurrent callers are queued (internal actor or async serial gate). Today `TextExtractor` holds one shared `private var webView` (TextExtractor.swift L12) that `extractFromWeb` assigns (`self.webView = webView`, L27) and later nils (`self.webView = nil`, L42); two overlapping web extractions clobber this single reference and can cross-contaminate. The spec pins serialization as a required invariant so overlapping `ingest()` calls do not share/clobber the single WKWebView.
2. **URL normalization is trim + conditional `https://` prepend.** `normalizedURL(from:)` trims whitespace/newlines and prepends `https://` only when the string lacks an `http://`/`https://` prefix, returning `nil` for un-constructable URLs (mirrors `loadURL` L232-236 and `saveForLater` L284-288). PIN.
3. **Web extraction 20s hard timeout.** Extraction throws `URLError(.timedOut)` when page load exceeds 20s (TextExtractor.swift L32-35). PIN.
4. **Empty extraction is an error, not empty content.** A page yielding empty trimmed body throws `URLError(.zeroByteResource)` with `"No readable text could be extracted from this page."` (TextExtractor.swift L44-49). PIN.
5. **Deep link is scheme/host/param strict.** `parseDeepLink` accepts only `scheme == "pagehum"`, `host == "open"`, and returns the `"url"` query item; anything else → `nil` (handleOpenURL L215-217). PIN.
6. **Shared-URL drain is one-shot.** `drainSharedURL()` reads the key, then `removeObject(forKey:)` + `synchronize()` before returning, so a second call returns `nil` (checkForSharedURL L206-211). PIN.
7. **App-group identifiers are a cross-target contract.** `appGroupID`/`sharedURLKey` here must byte-for-byte equal `ShareViewController`'s (`"group.com.test.mier.hello"` / `"SharedURL"`, ReaderModel L201-202 ↔ ShareViewController L6-7); the writer (share extension, ShareViewController L55-58) and this reader must agree.
8. **Ingestion mutates neither the audio store nor transport.** `ingest`/`prepareText` must NOT clear `audioCache`/`skippedSentences` (removes the inline clear at L278) and must NOT call `stop()` (removes the inline `stop()` at L252). The CLAUDE.md rule "clear `audioCache` and `skippedSentences` together" is honored by delegating to `SentenceAudioStore.reset()` (Step 2), invoked by the applier's `contentReplaced`/`willReplaceContent` sequencing — not here.
9. **No MLX / audio work on this path.** This unit performs only text extraction + segmentation; the global MLX-on-`DispatchQueue.global`/`withCheckedContinuation` rule is N/A here. PDF extraction may use `Task.detached` (TextExtractor.swift L236) precisely because it is PDFKit, not MLX — this is allowed and must be preserved.

## Failure modes
- Garbage URL (e.g. contains spaces / not constructable) → `normalizedURL` returns `nil` → `ingest(rawURL:)` throws `"Invalid URL"`; applier sets `errorMessage` and resets `isLoading`. PIN message (L236/L288).
- Whitespace-only text → `ingest(text:)` throws `"Please enter some text"` (L242-245). PIN.
- Page load > 20s → `URLError(.timedOut)` propagates → `errorMessage` set, `isLoading` reset (matches `load` catch L259-262). PIN.
- Page with no readable text → `URLError(.zeroByteResource)` + descriptive message. PIN.
- PDF that cannot be opened → `URLError(.cannotOpenFile)` (TextExtractor L237). PIN.
- **Concurrent-extraction clobber (CURRENT BUG → FIX):** two overlapping `ingest(rawURL:)` today share the single `TextExtractor.webView` (L12/L27/L42); the second can reset/reassign it mid-flight, yielding cross-contaminated or nil-webView results. Invariant 1 fixes this by serializing extractions.
- Deep link with wrong scheme/host/missing `url` param → `parseDeepLink` returns `nil`; the pending URL is left untouched (handleOpenURL early-return L215-219). PIN.
- `extractForSaving` with no persistence context: today `saveForLater` returns early after extraction when `modelContext == nil` (L294), swallowing the result. In the new shape `extractForSaving` always returns the `ReadingContent`; the nil-context early-return and the `try? ctx.save()` swallow (L304) move to `ProgressStoring` (Step 4) and are out of scope here.

## Non-goals
- **Sentence splitting algorithm** — owned by `SentenceSegmenting` (Step 1); this unit calls `splitIntoSentences` to fill `IngestedDocument.sentences` but must not re-implement the 400-char / clause / word-boundary logic (L834-890).
- **Clearing `audioCache`/`skippedSentences`** — owned by `SentenceAudioStore.reset()` (Step 2), triggered via the applier's `contentReplaced` event; removes the clear at L278.
- **Stopping/rebuilding playback** — owned by `PlaybackControlling` (Step 10); removes the inline `stop()` at L252, replaced by caller-sequenced `willReplaceContent`.
- **Generation lifecycle** (`startPipeline`/`generationTask`) — owned by `GenerationPipeline` (Step 9).
- **SwiftData persistence** (`PlaylistItem` insert/save, `currentPlaylistItemID`, resume `lastSentenceIndex`) — owned by `ProgressStoring` (Step 4); removes the inline inserts at L296-304 and L358-361 and the mapping-then-insert of `saveToPlaylist` (L344-362). This unit only supplies the `("url"|"pdf"|"text", sourceURL)` mapping values for the source; the insert belongs to Step 4.
- **Writing `@Published` reader/loading state and seeding resume index/progress** — owned by the root `ReaderStateApplier` (replaces `prepareTextPublic` L265-271 and the assignments in `load` L250-263).
- **Storing/projecting `pendingSharedURL`** — the `@Published` field stays on the composition root; `SharedURLInbox` only computes the drained/parsed value.

## Test manifest
- `normalizedURL(from:)` prepends `https://` and trims surrounding whitespace. [off-device]
- `normalizedURL(from:)` returns `nil` on un-constructable garbage input. [off-device]
- `ingest(text: "   ")` (whitespace-only) rejects with error `"Please enter some text"`. [off-device]
- `parseDeepLink(pagehum://open?url=...)` returns the encoded target URL (drives pending). [off-device]
- `parseDeepLink` with wrong scheme/host/missing param returns `nil` (ignored). [off-device]
- `drainSharedURL()` is a one-shot read: first call returns the stored value, second call returns `nil` (injected `UserDefaults` suite). [off-device]
- source mapping `.url` → `("url", url.absoluteString)`. [off-device]
- source mapping `.pdf` → `("pdf", url.lastPathComponent)`. [off-device]
- source mapping `.text` → `("text", nil)`. [off-device]
- extractor throwing `URLError(.timedOut)` (fake `TextExtracting`) → error surfaced, `isLoading` reset by applier. [off-device]
- **Concurrency regression:** two overlapping `ingest()` calls are serialized and not cross-contaminated (pins invariant 1). [off-device]
- (Not in CI) real `TextExtractor` web (WKWebView) and PDF (PDFKit) round-trips are simulator/device-only; off-device coverage uses `FakeTextExtracting`. [device-only]

