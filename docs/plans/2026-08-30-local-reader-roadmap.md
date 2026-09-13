# Pagehum Local Reader Roadmap

Date: 2026-08-30
Status: Validated product direction
Related research: [URL reader mode and offline preservation](2026-08-31-url-reader-mode-research.md)

## 1. Product Decision

Build Pagehum into a private, local-first listen-later inbox for personal daily use.

The target is the workflow quality of a paid read-it-later app, without subscriptions,
accounts, billing, or cloud infrastructure. Pagehum should accept a mixed stream of web
articles, PDFs, and text; help the user process that stream; and make listening a first-class
way to read. The product promise is:

> Capture anything worth reading, listen or read offline, keep the useful passages, and
> always be able to find or export them.

The nearest workflow benchmark is Readwise Reader/Matter rather than Speechify. Pagehum's
distinct advantage is private on-device Kokoro synthesis with no usage limits or cloud TTS.

## 2. Current Product Assessment

### Strong and already implemented

- On-device Kokoro 82M synthesis with 28 bundled voices.
- Background playback, audio interruption handling, and lock-screen transport controls.
- Gapless look-ahead scheduling through `GaplessSentenceScheduler`.
- Word-level timing and highlighting for the local reader.
- URL, PDF, and pasted-text extraction.
- Full extracted text stored in SwiftData for offline reading and synthesis.
- Per-sentence progress persistence and resume.
- Sentence audio disk cache with AAC audio, timing sidecars, SHA-256 keys, and LRU eviction.
- Code-block-aware article segmentation.
- Listening-time history and streaks.

The top-level specification and `docs/IMPROVEMENT_PLAN.md` are stale about A1/A2. Both disk
caching and gapless scheduling are present and connected in the current implementation.

### Product gaps

The app currently behaves like a TTS input screen plus playback history. It does not yet form
a durable reading workflow:

- Home is an import form instead of the user's reading inbox.
- Library state combines playback completion with content organization.
- There is no archive, favorite, tagging, full-text search, multi-select triage, or deduplication.
- There are no durable highlights, bookmarks, notes, or exports.
- Share intake is a single URL slot; rapid shares can overwrite one another, and arbitrary text
  or PDFs are not retained.
- Extraction failures lose the intake request instead of leaving a retryable job.
- The live web page is the primary URL reader even though it can diverge from saved extracted
  text and cannot support durable local annotations reliably.

### Trust and polish gaps

- Expanding the minimized playback control pauses playback.
- Shared/deep-linked URLs always route to `ReaderView` from the app entry point instead of using
  the normal source-aware routing.
- Home forces the URL keyboard open whenever it appears.
- First play presents a pause icon before audio is ready instead of a Preparing state.
- Now Playing duration uses sentence counts as if they were media seconds.
- Twenty-second skips use a fixed character-rate estimate and can land unpredictably.
- Synthesis failures silently omit sentences.
- Accessibility labels, Dynamic Type behavior, and non-color reading cues are incomplete.
- The SwiftData container is created with `try!`, making store initialization failure fatal.
- There is no unit-test target despite several intentionally testable components.

## 3. Core Workflow

The primary loop is:

`Capture -> Triage -> Read/Listen -> Mark/Note -> Archive or Later -> Find/Export`

### Library home

The app should open to a compact library with these areas:

1. **Continue**: the most recently active document with progress and one-tap resume.
2. **Inbox**: newly captured documents that have not been triaged.
3. **Later**: documents deliberately kept in the active queue.
4. **Archive**: processed documents retained for search and reference.

A persistent add command exposes URL, file, and pasted-text import. The share extension remains
the fastest capture path from other apps.

Completion and archive are separate concepts. Completion describes reading/listening progress;
archive describes whether the item still needs attention.

### Reader

Saved extracted content becomes the primary reader for every source. The original URL or retained
PDF remains available through **View Original**. This gives highlighting, search, offline behavior,
and progress one stable local representation.

Selecting text creates a highlight. A playback bookmark captures the current sentence and audio
position. Both can receive an optional note or tags and appear in the same annotations list.

### Organization

The first release includes lifecycle state, favorites, free-form tags, search, and multi-select
actions. It deliberately excludes folders and collections until real usage shows that tags and
search are insufficient.

## 4. Data Model

Evolve `PlaylistItem` incrementally rather than replacing it immediately. Add fields with safe
defaults and migrate existing rows on launch.

### Document fields

- Stable UUID independent of SwiftData's `PersistentIdentifier`.
- Canonical source identity for deduplication.
- Source kind: URL, PDF, or text.
- Title, author/byline, site name, original URL, and retained local file reference when applicable.
- Extracted body, text preview, word count, and content revision.
- Added, updated, last opened, and archived dates.
- Lifecycle state: inbox, later, archive.
- Ingest state: processing, ready, failed.
- Favorite flag and normalized tags.
- Playback progress, last sentence index, playback text offset, and known/estimated duration.
- Last ingest error suitable for display and retry.

Playback completion should be derived from progress instead of stored in the lifecycle state.

Store playback position as a **UTF-16 offset into the canonical text**, not only as a sentence
index. Sentence indices are invalidated by any change to segmentation, and the reader work
changes segmentation from whole-document to per-block. Converting existing `lastSentenceIndex`
values to offsets must happen on the current code path, in Phase 0 — see
[§9.1 of the reader research](2026-08-31-url-reader-mode-research.md).

### Annotation fields

Add a SwiftData `Annotation` model containing:

- Stable UUID and parent document UUID.
- Kind: highlight or bookmark.
- Quoted text and optional note.
- Color and normalized tags.
- Created and updated dates.
- UTF-16 source offsets for fast rendering.
- Exact quote plus nearby prefix/suffix for anchor recovery.
- Sentence index and audio position when created during playback.

Offsets are valid within a content revision. Quote context permits best-effort re-anchoring after
re-extraction.

### Import jobs

Persist `ImportJob` records with a stable UUID, payload reference, source kind, state, retry count,
and last error. A ready `PlaylistItem` is committed only after extraction succeeds. Failed jobs
retain their original payload and can be retried or deleted.

## 5. Architecture

Do not complete the entire replaceability refactor before delivering product value. The existing
plan is directionally sound, but extracting ten units first would delay the daily-use workflow.
Introduce only the boundaries required by the features:

- `LibraryStore`: import/dedup, lifecycle transitions, queries, delete, and export.
- `ImportInbox`: app-group manifest queue and staged payload ownership.
- `AnnotationStore`: highlight/bookmark/note CRUD and anchor recovery.
- `ReaderDocument`: immutable content revision (sanitized HTML, deterministic plain-text
  projection, block index) plus a separate append-only asset set. The two have different
  lifetimes: anchors bind to the revision, media retries mutate only the asset set. Contract in
  [§4 of the reader research](2026-08-31-url-reader-mode-research.md).
- Existing playback pipeline: emit accurate position, duration, preparation, and failure events.

`ReaderModel` must not acquire library search, annotation, import queue, or export algorithms.
Those concerns should be independently testable and injected or used directly by their views.

Search should begin as debounced local filtering across document metadata/body and annotation
text. For a personal library this is simpler and adequate. Add SQLite FTS5 only after profiling
demonstrates unacceptable latency with representative data.

## 6. Durable Capture

Replace the single `SharedURL` app-group key with a queued import inbox:

1. The share extension creates a UUID manifest in the shared app-group directory.
2. URL payloads are stored in the manifest; text and file payloads are copied to staging files.
3. The extension atomically renames the completed manifest into the ready queue.
4. The main app drains ready manifests into persistent `ImportJob` records.
5. Extraction runs serially and transitions each job to ready or failed.
6. Successfully owned payloads move into app storage; failed payloads remain retryable.

This prevents overwrite loss, supports multiple rapid shares, and establishes one intake path for
URL, text, and PDF. New formats should use the same manifest contract later.

URL identity should remove common tracking parameters and normalize scheme/host before deduping.
A duplicate opens or updates the existing document rather than creating a second progress history.
The original URL must still be retained exactly for View Original.

## 7. Playback Quality Contract

- Tapping Play enters Preparing until the first playable buffer is available.
- Audio begins, pauses, resumes, and seeks without duplicate playback or hidden state changes.
- The minimized control expands without changing playback state.
- Known buffer durations replace character estimates progressively; estimates are explicitly
  treated as estimates until enough audio is available.
- Now Playing uses media seconds, a useful title/author, playback rate, and artwork when available.
- A sleep timer supports 15, 30, 45, and 60 minutes plus end of document.
- A playback bookmark can be created without leaving the reader.
- Failed sentences are skipped to keep the session moving, but the session reports how many were
  omitted and offers retry.
- Saved extracted text remains readable and synthesizable offline. Cached audio is an optimization,
  not a correctness requirement.

## 8. Failure Handling

- Capture is durable before extraction starts.
- Extraction and persistence are atomic from the library user's perspective.
- Import failures remain visible and retryable with the original payload intact.
- SwiftData initialization and save failures produce recoverable UI where possible, never `try!`.
- Concurrent extraction is serialized because `TextExtractor` owns mutable `WKWebView` state.
- Corrupt audio cache entries continue to degrade to cache misses and regeneration.
- Deleting a document explicitly handles its annotations and any owned source file. Shared cache
  entries remain managed by LRU and are not assumed to belong to one document.
- Schema migration is tested against a fixture representing the current `PlaylistItem` shape.

## 9. Test Strategy

Create a Mac-runnable unit-test target before changing persistence or capture.

### Unit and integration coverage

- Existing `GaplessSentenceScheduler` contract.
- URL normalization, tracking-parameter removal, and deduplication.
- Inbox/later/archive transitions and completion independence.
- Legacy status migration and stable ID assignment.
- Import manifest atomicity, ordering, retry, and crash recovery.
- Annotation creation, rendering ranges, and quote-context re-anchoring.
- Sentence-index-to-text-offset conversion against fixtures of the current `fullText` shape,
  including bodies carrying `ArticleSegmenter` markers.
- Reader document invariants: block ranges tile the plain-text projection in document order, and
  the projection is byte-identical across text sizes and viewport widths.
- Search across titles, bodies, highlights, and notes.
- Export round trips for Markdown and JSON.
- Preparing, sleep timer, resume, skip, and finish state transitions.
- Progress and duration mapping into Now Playing snapshots.

MLX is isolated behind a fake synthesizer for off-device tests. A physical-device smoke suite covers
real synthesis, gapless transitions, memory pressure, interruptions, route changes, background
playback, lock-screen commands, speed/voice changes, and cache hits.

Use local HTML/PDF fixtures for extraction regression tests. Network pages are unsuitable as the
only extraction tests because their markup and availability change independently of the app.

## 10. Delivery Plan

### Phase 0: Trust pass and harness

- Add the test target and fakes required for non-MLX behavior.
- Fix minimized-control pause, source-aware deep-link routing, and forced Home focus.
- Replace fatal container initialization with a recoverable path.
- Add Preparing and surfaced playback-failure state.
- **Convert every `lastSentenceIndex` to a UTF-16 text offset while the current segmenter is
  still in place.** This is the one item in the whole plan that becomes impossible if deferred:
  reconstructing the old sentence array requires the old code path, so once per-block
  segmentation ships, unconverted positions are unrecoverable.

Exit condition: existing playback behavior has focused regression coverage, the obvious trust
breakers are gone, and no saved progress depends on segmentation staying identical.

### Phase 1: Document and import foundation

- Add stable document IDs, metadata, lifecycle/ingest fields, and migration.
- Add `ImportJob`, `LibraryStore`, and canonical URL deduplication.
- Replace `SharedURL` with queued app-group manifests.
- Accept URL, plain text, and PDF from the share extension.
- Retain failed jobs and owned source payloads for retry.

Exit condition: rapid mixed-source capture cannot overwrite or silently lose an item.

### Phase 2: Library home

- Make Continue/Inbox/Later/Archive the first screen.
- Move URL/file/text controls into an add sheet or menu.
- Add favorites, search, filters, and multi-select lifecycle actions.
- Open the stable local reader by default; add View Original.

Exit condition: the entire active queue can be understood and triaged without opening each item.

### Phase 3: Highlights, bookmarks, and export

- Add annotation persistence and stable anchoring.
- Add text selection highlights and current-position playback bookmarks.
- Add notes, tags, per-document annotation lists, and global annotation search.
- Export selected documents or the full library as Markdown and JSON.

Exit condition: an idea captured during reading or listening can be found and exported later.

### Phase 4: Listening polish

- Add sleep timer and a one-tap bookmark control.
- Replace sentence-count Now Playing data with duration-aware snapshots.
- Improve resume/seek with known sentence durations and cache reuse.
- Add generation-failure summaries and retries.
- Complete VoiceOver, accessibility labels, Dynamic Type, and non-color cues.
- Make autoplay on resume an explicit user preference.

Exit condition: device testing finds no confusing playback state, and background/lock-screen use
is trustworthy for long sessions.

## 11. Deferred Scope

Do not build these until daily use reveals a repeated need:

- OCR and camera capture.
- EPUB and DOCX import.
- RSS feeds and newsletter forwarding.
- Cloud accounts and cross-device sync.
- AI summaries, chat, quizzes, or recommendations.
- Folders, collections, and spaced review.
- A full-article exported M4A format.

## 12. Success Measures

Use local product measures rather than growth metrics:

- Capture success: every accepted share becomes a ready item or a visible retryable job.
- Capture speed: URL share completes without requiring the app to remain foregrounded.
- Resume speed: a recent item is reachable and playable from launch in two actions or fewer.
- Audio trust: play-to-audible state is explicit; no unintended pause when opening controls.
- Retrieval: a remembered title fragment, body phrase, highlight, or note is findable offline.
- Portability: all documents and annotations can leave the app in readable and structured forms.
- Stability: migration preserves the existing library and progress; core non-MLX tests run without
  a physical device.

## 13. Recommended First Implementation Slice

Start with Phase 0 as one small release, then implement Phase 1 vertically:

1. Add safe-default document fields and migration tests.
2. Introduce the app-group manifest format for URLs only.
3. Drain manifests into `ImportJob`, extract, dedupe, and commit a ready document.
4. Add failed-job retry UI.
5. Extend the proven manifest path to text and PDF.

This sequence tests the new architecture with the smallest payload before adding file ownership and
security-scoped resource complexity.