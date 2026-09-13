# URL Reader Mode and Offline Preservation Research

Date: 2026-08-31
Status: Research recommendation — revised after implementation scrutiny
Related roadmap: [Pagehum Local Reader Roadmap](2026-08-30-local-reader-roadmap.md)

> **Revision note (2026-08-31, second pass).** The original recommendation (Option C) survived
> review unchanged. This revision resolves an internal contradiction in the document contract,
> pins down three steps that were named but not specified (sanitization location, plain-text
> projection, CSP mechanism), adds the missing migration story for existing library rows, and
> maps the delivery sequence onto the roadmap's phases. Sections 4, 5, 9, 10 and 12 are the
> substantive changes.

## 1. Question

How do Safari and read-it-later applications turn a URL into a clean reader view while
retaining useful links, media, and text structure, and how do they make that result work
offline?

There are two different fidelity goals:

1. **Semantic reader fidelity** preserves the article's meaning and structure: headings,
   paragraphs, emphasis, lists, quotes, code, tables, links, images, and captions. The app
   supplies typography and layout.
2. **Page fidelity** preserves the publisher's visual page, CSS, fonts, scripts, embeds, and
   interaction as closely as possible.

Reader applications generally optimize for semantic fidelity. Full-page archivers optimize
for page fidelity. One representation does not serve both jobs well.

## 2. What Existing Products Do

### Safari Reader and Reading List

Apple exposes the behaviors as two related but distinct features:

- Reader formats a supported webpage to show the relevant text and images.
- Reading List can automatically save webpages for offline reading.

Apple does not document Safari's article-selection algorithm or Reading List's on-disk
format as public application APIs. The useful product lesson is the separation: a cleaned
reader presentation is not the same concern as acquiring and retaining an offline copy.

`WKWebView.createWebArchiveData` is public on iOS 14 and later and can capture the current
web view as a web archive. It is suitable for an optional original-page snapshot, but it is
not a good canonical reader representation: it retains much more untrusted and irrelevant
page state, is harder to annotate, and has less predictable storage cost.

### Firefox and Mozilla Readability

Mozilla Readability is the clearest public model for extraction. It receives a rendered DOM
and returns both:

- `content`: processed article **HTML**;
- `textContent`: the same article with tags removed;
- metadata including title, byline, excerpt, site name, language, direction, and publication
  time.

Readability resolves relative image and hyperlink URLs when the source document URL is
provided. Its default serializer returns `innerHTML`, or a caller can retain the resulting
DOM for further processing. It intentionally does not sanitize untrusted HTML; Mozilla
recommends a sanitizer such as DOMPurify plus a Content Security Policy before rendering.

Two operational details matter for an iOS port and are easy to miss:

- Readability **mutates the document it is given**, so it must run against a clone.
- Its lazy-image handling (`_fixLazyImages`) is partial. It does not guarantee that every
  `img` in the returned HTML points at a real, fetchable asset. Section 6 covers the
  consequences.

This is the main architectural lesson for Pagehum: extraction should retain cleaned HTML
and derive plain text from it. Returning only `textContent` throws useful information away.

### Omnivore

Omnivore's open-source pipeline shows how a read-it-later product builds on Readability:

- A browser extension can send the rendered document; a Puppeteer service is the fallback
  for URL-only saves and JavaScript-heavy pages.
- A fork of Mozilla Readability produces `readableContent` HTML and fixes relative URIs.
- The service can retain `originalContent` separately from cleaned `readableContent`.
- Stable `data-omnivore-anchor-idx` attributes are added to HTML for progress and
  highlights.
- The Apple client persists `htmlContent` and metadata in Core Data, then injects that local
  HTML into an app-owned reader shell.
- Images can be rewritten through a signed image proxy. PDFs are downloaded as owned local
  files.

Omnivore demonstrates the right reader representation and anchor strategy. Its proxy-based
image path is not sufficient by itself for a strict local-only guarantee because a proxy URL
still needs a network or a separate client cache.

**Note:** Omnivore was discontinued in late 2024 following its acquisition. It remains a
valid design reference as an archived codebase, but it is a snapshot, not a maintained
product, and its links may rot. Do not plan on the repository staying reachable.

### Readwise Reader

Reader is offline-first and lets users choose which library sections are cached. Opening an
individual document also caches it. Its December 2025 Offline v2 description makes an
important limitation explicit: most documents cache text content for offline use, while
EPUBs also include images.

This is evidence that "article available offline" and "all article media available offline"
must be separate, visible contracts. Selective caching is also a useful response to storage
growth, but Pagehum should not call media available offline until it owns the corresponding
files.

### Readeck

Readeck is the closest match for the requested preservation behavior:

- It stores article text and images when a link is saved.
- Except for videos, its reader does not need to request resources from the publisher.
- Each bookmark is an immutable ZIP containing HTML, images, and related parts.
- The application serves or converts parts of that package into a webpage or EPUB.
- Its browser extension sends the full rendered page and supports user-selected content when
  server-side URL extraction is incomplete.

Readeck reports roughly 300 KB per typical bookmark, while warning that image processing can
cause memory peaks. The exact number is workload-dependent, but its immutable-package design
is a strong fit for local ownership, export, backup, and crash-safe replacement.

Pagehum should adopt the immutability property but **not** the single-ZIP container. A
directory of files can be served directly by a `WKURLSchemeHandler` with per-request
authorization against the manifest, whereas a ZIP would have to be extracted into memory or
a temporary directory on every open. Export and backup — the reasons to like the ZIP — are
better served by zipping the directory on demand at export time.

### Instapaper and Historical Pocket

Instapaper publicly promises synchronized articles and videos for offline reading, but its
current parser and storage implementation are proprietary. It is useful as a product
benchmark, not as an implementation reference. Pocket shut down in 2025 and should only be
treated as a historical interaction benchmark.

### SingleFile and Full-Page Archivers

SingleFile captures a faithful complete webpage as one HTML file by embedding or packaging
page resources. This is valuable when exact preservation matters, and it can complement a
reader representation. It is a poor primary document for Pagehum because navigation,
advertising, arbitrary styles, scripts, and unrelated page structure make TTS, highlighting,
search, and stable progress much harder.

## 3. Options for Pagehum

### Option A: Keep Plain Text and Add Ad Hoc Metadata

Store the current text plus side arrays for links and images.

This looks small initially but recreates an HTML document model poorly. Offsets drift during
sentence segmentation and re-extraction, nested formatting is difficult, and rendering links,
lists, tables, captions, and inline emphasis becomes a growing set of special cases.

The existing `ArticleSegmenter` marker format is already a limited instance of this pattern,
and it works only because a code block is opaque, atomic, and never needs an offset into the
prose around it. Links, emphasis, and images have none of those properties.

**Verdict:** Do not pursue.

### Option B: Typed Native Block Model

Convert the article into native blocks such as heading, paragraph, list, quote, code, image,
and table, then render each block in SwiftUI.

This gives excellent native control and testability. It also requires a rich schema, custom
selection across blocks, table and inline-style rendering, migrations as new elements are
supported, and a fallback for structures the schema cannot express.

**Verdict:** Viable later if native rendering becomes a product requirement, but too costly
for the first fidelity upgrade.

### Option C: Sanitized Semantic HTML Package

Store sanitized article HTML, locally owned resources, metadata, and a derived text/block
index. Render the HTML in an app-owned offline `WKWebView` shell and use the derived index for
TTS, search, progress, and annotation anchoring.

This follows Mozilla Readability and Omnivore for reader semantics, and Readeck for durable
resource ownership. Web technologies handle nested inline formatting and selection, while
Pagehum still controls all styling, navigation, scripts, and storage.

**Verdict:** Recommended.

## 4. Recommended Document Contract

The canonical saved artifact should be an immutable `ReaderDocument` content revision, not a
plain string and not a full webpage archive.

### 4.1 Content and assets are separate lifetimes

The first draft of this document placed `assets/` inside the revision directory and called
the whole revision immutable. That contradicts the retry behavior promised in Section 7:
re-downloading one failed image would either mutate a committed revision or fork a new one,
and forking invalidates every highlight and the saved playback position in order to fix a
JPEG.

Split the two lifetimes:

- **Content revision** — immutable once committed. All text anchors bind here.
- **Asset set** — append-only, content-addressed, shared across revisions of the document.
  Media completeness is a property of this set, not of the revision.

```text
ReaderDocuments/<document-id>/
  assets.json                          # mutable: original URL -> hash, MIME, bytes, state, error
  assets/
    <sha256>.<validated-extension>     # append-only, content-addressed
  content/
    <revision>/
      manifest.json
      article.html
      text.txt
      blocks.json
  original/                            # optional: retained PDF, or a web archive snapshot
```

Because assets live outside the revision, `article.html` must **not** reference them by a
revision-relative path. It should use a stable app-owned form — for example
`pagehum-asset:///<sha256>.<ext>` — that the reader shell's scheme handler resolves against
the document's asset directory. Content addressing also means a re-extraction reuses every
unchanged image for free.

### 4.2 Nothing stores the article text twice

The first draft stored article text three times: in `article.html`, in `text.txt`, and again
inside `blocks.json`. Three independently written copies of the same text will drift, and the
drift surfaces as off-by-one anchor bugs long after the write that caused it.

Assign one role to each file:

- `article.html` is the canonical **rich** representation, with semantic elements and stable
  `data-pagehum-block-id` attributes.
- `text.txt` is the canonical **plain-text projection**, produced once at capture.
- `blocks.json` is the **join** between them. Per block it stores the block ID, kind (prose,
  heading, code, image caption, table, …), a speakable flag, and a UTF-16 range into
  `text.txt`. **It stores no text of its own.**

The testable invariant: block ranges tile `text.txt` in document order with defined joiners,
and for every block, the slice of `text.txt` at its range is that block's plain text. This is
a property test, not a comment.

### 4.3 The plain-text projection must be deterministic

`text.txt` must be a pure function of the sanitized DOM, computed once at capture and stored.

It must **not** be derived from `innerText` in the reader shell. `innerText` is layout-aware:
it depends on the applied CSS, the current Dynamic Type size, and the viewport width. A
projection computed at render time would therefore differ between devices and between text-size
settings, shifting every UTF-16 offset and silently corrupting anchors that were valid when
written.

This is a live habit in the current code, not a hypothetical: `TextExtractor.readerJS` ends at
`clone.innerText || clone.textContent`. Carrying that approach into an anchored world is the
single most likely source of hard-to-reproduce highlight and progress bugs.

### 4.4 Manifest contents

`manifest.json` (per content revision) should contain:

- schema and extraction versions;
- original URL, final URL after redirects, and canonical URL;
- title, byline, site name, excerpt, language, direction, and publication date;
- content hash, creation date, and the projection's joiner rules;
- the list of asset hashes this revision references.

`assets.json` (per document, mutable) should contain, for every discovered resource: the
original URL, local hash and relative path, MIME type, byte count, acquisition state, and the
error when unavailable. The document's media state — `complete`, `partial`, or `textOnly` — is
computed from this file against the current revision's referenced-asset list.

SwiftData should own searchable metadata, lifecycle state, progress, annotations, and the
package-relative path. Large media should remain in the package directory rather than as
SwiftData blobs.

### 4.5 One contract covers PDF and pasted text

The roadmap asks for "one stable local representation" for every source, but PDFs and pasted
text have no HTML. Two options:

1. **Recommended — synthesize minimal HTML for every source.** PDF text from PDFKit becomes
   paragraphs with page-boundary blocks; pasted text splits on blank lines. No layout fidelity
   is attempted, and the original PDF is retained under `original/` for View Original. The
   generator is small, and the payoff is one reader, one anchor model, one annotation
   implementation, and one search index.
2. **Rejected — let PDF and text keep the plain-text path.** This looks cheaper for one release
   and then permanently doubles the cost of highlights, search, progress, and export, because
   every one of those features has to be written twice and kept in agreement.

Choosing (1) means `ReaderView`'s current native sentence list is replaced for all sources, not
just URLs. Section 8 costs that.

## 5. Capture and Extraction Pipeline

```text
URL or rendered DOM
  -> load page in an ephemeral WKWebView
  -> wait for DOM quiescence (not just didFinish)
  -> in an isolated content world: clone the DOM, run Mozilla Readability
  -> sanitize with a strict allowlist, outside the publisher's JS context
  -> assign stable block IDs
  -> normalize links and discover media (resolve srcset / currentSrc / lazy placeholders)
  -> download and validate allowed resources into the document's asset set
  -> rewrite resource URLs to app-owned asset references
  -> derive text.txt and blocks.json from the final sanitized HTML
  -> atomically rename staging to the committed revision
  -> commit/update SwiftData metadata
  -> sweep orphaned packages and unreferenced assets
```

### 5.1 Run capture in an isolated content world

Everything in this pipeline that runs as JavaScript is currently exposed to the page it is
reading. A hostile or merely aggressive page can override `Node.prototype`, `document.querySelectorAll`,
`JSON.stringify`, or `Array.prototype.forEach` and tamper with the result. This is already true
of `TextExtractor.readerJS` today, and it becomes materially worse once the output is HTML that
gets rendered rather than text that gets spoken.

Run extraction in a `WKContentWorld` isolated world via `callAsyncJavaScript(_:arguments:in:)`
(iOS 14+). Isolated worlds share the DOM but not the JavaScript environment, so prototype
tampering by the page does not reach the extractor.

### 5.2 Sanitize outside the publisher's context

The original draft said "sanitize with a strict allowlist" without saying where. That step is
load-bearing for security, so the location is part of the design, not an implementation detail.

Sanitizing in the capture page's main world is not trustworthy for the reason above — DOMPurify
running in a context the page controls can be neutered before it runs. Two acceptable placements:

1. Run DOMPurify in the same isolated content world as extraction. Cheapest, and adequate.
2. Serialize Readability's output, then re-parse and sanitize it in a second `about:blank`
   `WKWebView` with `allowsContentJavaScript` disabled for page content. Strongest isolation,
   one extra webview.

Either way, the allowlist is applied to a DOM that the publisher's scripts can no longer reach.

### 5.3 "The final rendered DOM" needs a definition

The pipeline says "clone the final rendered DOM" without saying how finality is determined. The
current heuristic is `didFinish` plus a fixed 500 ms sleep under a 20 s cap
(`TextExtractor.extractFromWeb`), and that heuristic is a large part of why URL-only extraction
is unreliable on client-rendered pages.

The plan's answer to that unreliability is a Safari Web Extension, which is the most expensive
item in the delivery sequence. A cheap intermediate should land first: a `MutationObserver`
quiescence check — resolve when no subtree mutations have occurred for ~400 ms, or when a hard
ceiling is reached — plus a short scroll pass to trigger `IntersectionObserver`-based lazy image
loading before the DOM is cloned. This measurably raises the hit rate of step 1 without any
extension work.

### 5.4 Commit is two steps, so it needs a sweeper

Renaming a staging directory into place is atomic on APFS, but the SwiftData save that follows
it is a second, separate commit. A crash between them leaves a package on disk that no row
references. Superseded revisions create the same garbage on re-extraction.

Add a startup sweep that deletes package directories with no SwiftData row, content revisions no
longer referenced by their document, and assets in `assets/` referenced by no retained revision.
Without it, storage grows in a way the user cannot see or explain.

### 5.5 Authenticated and client-rendered pages

For normal URL intake, Pagehum can continue loading the page in a hidden `WKWebView`. For
authenticated, paywalled, or heavily client-rendered pages, URL-only extraction will remain
unreliable even with quiescence detection. Readeck and Omnivore solve this with browser
extensions that send the already rendered DOM. A future Safari Web Extension or
JavaScript-preprocessing action can provide the same fallback without storing publisher
credentials in Pagehum.

The capture should use an ephemeral `WKWebsiteDataStore` unless a user explicitly needs an
authenticated browser handoff. Redirects and the final base URL must be retained so relative
links and resources resolve correctly.

## 6. Preservation Policy

Preserve in the canonical reader document:

- headings, paragraphs, line breaks, emphasis, strong text, and horizontal rules;
- ordered and unordered lists;
- blockquotes, preformatted text, and inline code;
- safe tables;
- hyperlinks and in-document fragment links;
- images, picture/source candidates, alt text, figures, and captions;
- safe `sub`, `sup`, `mark`, language, and text-direction semantics.

Remove or replace:

- scripts, event handlers, forms, inputs, cookie prompts, navigation, ads, and comments;
- publisher stylesheets, fonts, trackers, and pixels;
- arbitrary iframes and executable embeds;
- `javascript:`, unsafe `data:`, and non-HTTP(S) source URLs.

### 6.1 Image acquisition is harder than "download the src"

A bare `URLSession` pass over the `img` elements in Readability's output will fail more often
than the pipeline diagram suggests:

- Hotlink-protected CDNs return 403 without a `Referer` matching the article's final URL.
- Some hosts require the cookies the capture webview already holds.
- Lazy-loading placeholders resolve to 1×1 spacers or inline SVG shims; the real URL is in
  `data-src`, `data-srcset`, or only in `currentSrc` after the element has been scrolled into
  view. Readability's `_fixLazyImages` covers some of these patterns, not all.
- `srcset` requires picking a candidate at capture time, since the reader shell's viewport is
  not the publisher's.

Mitigations, in order of value: resolve `currentSrc` in the isolated world after the scroll pass
of §5.3; send the final URL as `Referer`; reuse the capture session's cookie store for asset
requests; and record the chosen `srcset` candidate in `assets.json` so retries are reproducible.

### 6.2 Embedded media needs an honest fallback

Direct images should be downloaded. Video, audio, social posts, maps, and interactive diagrams
should become a **titled placeholder card** carrying whatever caption text survived extraction
plus an **Open Original** link.

The first draft promised a "local poster/preview" for these. That is only achievable where a
poster is discoverable — a YouTube embed yields a thumbnail from its video ID, an HTML5 `video`
element may carry a `poster` attribute. A tweet, a Datawrapper chart, or a custom JS visualizer
yields nothing once the iframe is stripped. The contract should be "placeholder card, with a
poster when one is discoverable," not "poster."

Streaming video, DRM, expiring URLs, and script-based players cannot be promised offline.
Downloading direct audio/video can be a later opt-in with separate quotas.

External links remain clickable but are not themselves offline. The navigation delegate should
open them outside the local reader or offer to save them as another document.

## 7. Offline and Storage Contract

The UI and model should distinguish:

- **Text available offline:** a committed content revision exists with HTML, text, and block
  index.
- **Media complete:** every asset referenced by that revision exists locally and passed
  validation.
- **Media partial:** the document remains readable, with placeholders and retryable resource
  failures.
- **Original snapshot available:** an optional retained PDF or web archive exists separately.

Because the asset set is append-only and separate from the revision (§4.1), a media retry is an
ordinary additive operation: fetch, validate, write the content-addressed file, update
`assets.json`, recompute media state. The content revision is untouched, so no anchor, highlight,
or saved position is disturbed by fixing an image.

Saved article text is durable and must never be evicted automatically. If Pagehum promises
offline images, those images are also document data, not disposable cache. Storage controls may
offer text-only saving, Wi-Fi-only media downloads, per-document retry/removal, and total usage
reporting. They should not silently LRU-evict media while continuing to show the item as fully
offline.

### 7.1 Name the budgets

The first draft called for "a configurable per-document budget" without proposing numbers. The
app already ships a ~600 MB model, so media growth is not free headroom. Suggested starting
values, to be tuned against real captures:

- per-response ceiling: 5 MB, with the request cancelled rather than truncated;
- decoded-pixel ceiling: ~40 megapixels, to stop decompression bombs before they allocate;
- per-document media budget: 8 MB default, after which remaining assets are recorded as skipped
  and the document is marked partial;
- redirect limit: 5; per-asset timeout: 15 s; whole-document acquisition timeout: 60 s;
- a library-wide media total surfaced in Settings alongside the existing audio cache size.

Resource failures should mark the package partial rather than discard a successfully extracted
article. A MIME allowlist is checked against sniffed bytes, not the declared `Content-Type`.

## 8. Rendering, TTS, and Annotations

Load `article.html` in a local `WKWebView` with app-owned CSS and JavaScript only.

### 8.1 The CSP mechanism has to be chosen, not just named

"Apply a Content Security Policy" is not implementable as written, because how the policy is
delivered depends on how the document is loaded:

- `loadFileURL(_:allowingReadAccessTo:)` cannot set response headers, so the policy would have to
  live in a `<meta http-equiv="Content-Security-Policy">` tag inside `article.html`.
- A `WKURLSchemeHandler` returns a `URLResponse` the app constructs, so it can send real CSP
  headers — and it can additionally refuse any request whose path is not in the revision's
  referenced-asset list.

**Recommended: the scheme handler.** It is the only option that gives both a real header and
per-request authorization, and it is already required by §4.1 so that `article.html` can
reference assets outside its own revision directory.

Note that `allowsContentJavaScript = false` is not available as a blanket setting here, because
app-owned JavaScript performs highlighting and scroll sync. The policy therefore needs
`script-src` restricted to a per-load nonce or hash, with `default-src 'none'`, `connect-src 'none'`,
and `img-src` limited to the app's asset scheme. All link navigation must still be intercepted by
the navigation delegate.

### 8.2 Anchors and segmentation

Stable `data-pagehum-block-id` attributes connect the rendered HTML to `blocks.json`. Sentence
segmentation runs on each speakable block and records sentence ranges against the same content
revision. This preserves the current sentence-audio pipeline while allowing headings, links,
emphasis, lists, and images to render normally. Code blocks remain non-speakable or use the
current announcement behavior.

One consequence to plan for: today `splitIntoSentences` runs `NLTokenizer` across the **entire
body at once** (`ReaderModel.splitIntoSentences`). Segmenting per block changes the tokenizer's
context and will produce a different sentence array for the same article — sentences that
straddled a paragraph boundary split differently. This is the direct cause of the migration
requirement in Section 9.

Highlights should anchor to a content revision with block ID, UTF-16 range, exact quote, and
prefix/suffix context. That is more robust than indexing only the flattened article body and
matches the roadmap's annotation-recovery direction.

### 8.3 The native reader is replaced, and that is not free

Moving to an HTML shell retires `ReaderView`'s native rendering: the `LazyVStack` sentence list,
word-level highlighting in `SentenceView`, tap-to-seek per sentence, `CodeBlockView` cards, and
the Dynamic Type behavior that comes with SwiftUI text. All of it has to be reimplemented in
app-owned CSS and JavaScript inside the shell.

`WebReaderView` already performs sentence-level highlighting by JS injection, so the technique is
proven in this codebase, but it does not currently do word-level highlighting, seek-on-tap, or
code cards. This work is a real line item in the delivery sequence and was previously uncosted.

## 9. Migration from the Current Contract

Neither this document nor the roadmap previously said what happens to the existing library. The
existing rows are not a clean slate:

- `PlaylistItem.fullText` is a plain `String` that may contain `ArticleSegmenter` sentinel
  markers — U+E000/U+E001 wrapping base64 JSON code-block payloads.
- `PlaylistItem.lastSentenceIndex` indexes the array produced by
  `ArticleSegmenter.segment(fullText, splitProse: splitIntoSentences)`, which depends on
  whole-document `NLTokenizer` context. No character offsets are retained anywhere.

### 9.1 Convert progress to a text offset *before* the pipeline changes

Because §8.2 changes segmentation, `lastSentenceIndex` values become meaningless the moment
per-block segmentation ships — and they cannot be recovered afterwards, since reconstructing the
old array requires the old code path. The conversion is therefore a one-time forward migration
that must run **on the current code**, ahead of the rest of the work:

1. Segment `fullText` with the existing segmenter.
2. Resolve `lastSentenceIndex` to a UTF-16 offset into `fullText`.
3. Store the offset alongside (not instead of) the index.

From then on, playback position is stored as an offset into `text.txt` and resolved to a sentence
at load. This makes progress robust against every future segmentation change, and it uses the
same anchor model already proposed for highlights.

### 9.2 Legacy documents become revision 0

Existing rows should be migrated in place rather than re-extracted. Re-extraction needs the
network, silently changes content the user has already read, and fails outright on dead URLs.

Migration synthesizes a revision-0 package from the stored `fullText`: prose split on blank lines
into paragraph blocks, markers decoded into code blocks via the existing `ArticleSegmenter.decode`
path, media state `textOnly`, and no assets. The original URL is retained so the user can
explicitly re-capture a legacy document later to gain links, images, and structure.

### 9.3 Retire the marker format deliberately

Once code blocks are a block kind in `blocks.json`, the sentinel-marker format has no remaining
job. It should be retired, but only after §9.2 has consumed every stored `fullText` that contains
markers — the decoder must outlive the producer. Concretely: `TextExtractor` stops emitting
markers in step 1 of the sequence below; `ArticleSegmenter`'s decoder stays until migration is
confirmed complete across the installed base, then is deleted with its tests.

## 10. Delivery Sequence

The first draft carried its own five-step sequence that did not reference the roadmap's phases.
Two of the steps overlap roadmap phases that also touch persistence, and running them separately
would migrate the same rows twice. The reconciled sequence:

| Step | Work | Roadmap phase |
|------|------|---------------|
| 0 | Convert `lastSentenceIndex` to a UTF-16 text offset on the current code path (§9.1). | Phase 0 (trust pass) |
| 1 | Bundle Mozilla Readability; extraction returns sanitized semantic HTML plus its deterministic plain-text projection. Isolated content world, DOM quiescence, sanitization placement. Links and structure preserved; images stay remote during a short development-only transition. | Phase 1, with document fields |
| 2 | Immutable content revisions, the append-only asset set, image acquisition, URL rewriting, atomic commit, orphan sweep, explicit media completeness. The local document reader becomes primary for URLs. Synthesize revision-0 packages for legacy rows (§9.2) and for PDF/text sources (§4.5). | Phase 1 / Phase 2 |
| 3 | Stable block/sentence anchors, selection highlights, TTS synchronization against the shared revision, and the reader-shell reimplementation of word highlighting and seek (§8.3). | Phase 3 |
| 4 | Rendered-DOM Safari capture fallback for authenticated and JavaScript-heavy pages. | after Phase 3 |
| 5 | Optional `WKWebView` web archives, only if offline original-page preservation proves valuable enough to justify the storage and security cost. | deferred |

Step 0 is genuinely ordering-critical: it is the only item here that becomes impossible if it is
done late. Steps 1 and 2 must land in the same schema migration as the roadmap's Phase 1 document
fields, or existing rows get migrated twice.

The first production release should not claim media-complete offline reading until step 2 is
finished.

## 11. Implications for the Current Code

The current implementation in `TextExtractor.readerJS` performs a Readability-like node score
but ends with `innerText`/`textContent`. `ReadingContent.body`, `PlaylistItem.fullText`, and
`ReaderView` therefore have no representation for links, headings, lists, emphasis, figures, or
images.

The root change is not to improve the scoring regexes. It is to replace the flattened content
contract with a versioned `ReaderDocument`, while continuing to expose a derived plain-text
projection to the existing TTS pipeline. The roadmap's proposed immutable `ReaderDocument`
boundary is the right owner for this work and should be expanded to include HTML, block ranges,
and a resource manifest — with the content/asset lifetime split of §4.1.

The pieces of the current design that survive intact are worth naming, because they constrain the
port: `ArticleSegmenter`'s degrade-to-prose discipline should carry over to block parsing;
`CodeBlock` and its spoken announcement remain the model for non-speakable blocks; and the
gapless scheduler is untouched, since it consumes a sentence array whose provenance it does not
care about.

## 12. Open Decisions

Three forks in this document are recommendations rather than settled calls. Each changes scope
materially and should be confirmed before step 1 begins.

1. **One contract for PDF and pasted text (§4.5).** Recommended: synthesize HTML for all sources.
   Rejecting it keeps `ReaderView` alive as a second reader and doubles the cost of highlights,
   search, and export permanently.
2. **Sanitization placement (§5.2).** Recommended: DOMPurify in the isolated content world.
   The second `about:blank` webview is stronger but costs an extra webview per capture.
3. **Legacy documents are migrated, not re-extracted (§9.2).** Recommended: migrate in place to a
   `textOnly` revision 0, with explicit user-initiated re-capture available. Re-extracting on
   upgrade would give better fidelity at the cost of network dependence, silent content changes,
   and total failure on dead URLs.

## Sources

Load-bearing claims — Readability's return shape and lack of sanitization, its relative-URL
resolution, and `createWebArchiveData`'s availability — were verified against the primary sources
below. The product anecdotes (Readwise's Offline v2 details, Readeck's ~300 KB figure) are
illustrative rather than load-bearing and should be re-checked if any decision starts to depend
on them.

- [Apple: Hide distractions when reading articles in Safari](https://support.apple.com/guide/iphone/hide-ads-and-distractions-iphdc30e3b86/ios)
- [Apple: Save webpages to read later in Safari](https://support.apple.com/guide/iphone/save-pages-to-a-reading-list-iph1a4721132/ios)
- [Apple: `WKWebView.createWebArchiveData`](https://developer.apple.com/documentation/webkit/wkwebview/createwebarchivedata(completionhandler:))
- [Apple: `WKContentWorld`](https://developer.apple.com/documentation/webkit/wkcontentworld)
- [Apple: `WKURLSchemeHandler`](https://developer.apple.com/documentation/webkit/wkurlschemehandler)
- [Mozilla Readability](https://github.com/mozilla/readability)
- [DOMPurify](https://github.com/cure53/DOMPurify)
- [Omnivore source (archived)](https://github.com/omnivore-app/omnivore)
- [Readwise Reader FAQ: offline use and selective caching](https://docs.readwise.io/reader/docs/faqs)
- [Readwise Reader Offline v2](https://readwise.io/reader/update-dec2025)
- [Readeck source and architecture](https://codeberg.org/readeck/readeck)
- [Readeck FAQ: rendered-page extension fallback](https://readeck.org/en/docs/faq)
- [SingleFile](https://github.com/gildas-lormeau/SingleFile)
- [Instapaper](https://www.instapaper.com/)
