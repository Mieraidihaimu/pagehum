# Pagehum — Product Specification

A SwiftUI iOS app that reads articles, PDFs, and text aloud using on-device neural TTS (Kokoro 82M via MLX). Requires a physical iOS 18.6+ device — no Simulator support due to MLX.

---

## Dependencies (Swift Package Manager)

| Package | Purpose |
|---|---|
| `kokoro-ios` | Kokoro TTS engine + `MToken` word-timing tokens |
| `mlx-swift` | Apple MLX ML framework (Apple Silicon only) |
| `MisakiSwift` | English grapheme-to-phoneme (G2P) |
| `MLXUtilsLibrary` | `.npz` voice file reader, `MToken` definition |

Bundled resources (Git LFS):
- `Resources/kokoro-v1_0.safetensors` — ~600MB model weights
- `Resources/voices.npz` — 28 voice embeddings

---

## Targets

### Pagehum (main)
- Bundle ID: `com.test.mier.hello` (iphoneos)
- Background modes: `audio`
- App group: `group.com.test.mier.hello`
- Deep link scheme: `pagehum://`
- Entitlements: app sandbox, app group, network client, disable library validation

### PagehumShare (Share Extension)
- Bundle ID: `com.test.mier.hello.PagehumShare`
- Receives URLs shared from Safari/other apps
- Writes URL to shared `UserDefaults` under key `"SharedURL"`, then opens app via `pagehum://open?url=`

---

## Data Models

### `ContentSource` (enum)
```
.url(URL)      — web article
.pdf(URL)      — local PDF
.text(String)  — pasted text
```
Has computed `var webURL: URL?` — non-nil only for `.url` case. Used for view routing.

### `ReadingContent` (struct)
```
title: String
body: String          — plain text for TTS
source: ContentSource
byline: String?       — author, from og:meta or .author element
siteName: String?     — publication name, from og:site_name
```

### `PlaylistItem` (@Model, SwiftData)
```
title: String
sourceURL: String?    — full URL string (web) or PDF filename
sourceType: String    — "url" | "pdf" | "text"
fullText: String      — extracted body text saved at load time
textPreview: String   — first 200 chars
dateAdded: Date
lastPlayed: Date
progressPercent: Double
lastSentenceIndex: Int
status: String        — "queued" | "inProgress" | "completed"
```

---

## Core Model — `ReaderModel`

Single `@MainActor ObservableObject` singleton. Owns everything.

### Key published state
```swift
content: ReadingContent?
sentences: [String]              // NLTokenizer(.sentence) split of content.body
currentSentenceIndex: Int
currentWordText: String          // currently spoken word
currentTokenIndex: Int           // index into MToken array
progress: Double                 // 0.0–1.0
isPlaying: Bool
isPaused: Bool
isGenerating: Bool
isLoading: Bool
speed: Float                     // 0.75–3.0, applied via AVAudioUnitTimePitch.rate
selectedVoice: String            // e.g. "af_heart"
textSize: Double                 // reader font size, 12–32pt
errorMessage: String?
```

### Audio engine setup
```
AVAudioEngine
  └── AVAudioPlayerNode  →  AVAudioUnitTimePitch  →  mainMixerNode
```
Engine stays alive for the model's lifetime. Never call `audioEngine.stop()` — only `playerNode.stop()`.

`AVAudioSession` category: `.playback`, mode: `.spokenAudio`.

### TTS pipeline

**Generation (background `Task.detached`):**
- Iterates `sentences[]` up to `lookaheadCount = 3` ahead of `currentSentenceIndex`
- Calls `KokoroTTS.generateAudio(voice:language:text:speed:1.0)` → `([Float], [MToken]?)`
- Copies PCM floats into `AVAudioPCMBuffer`
- Stores as `SentenceAudio(buffer, tokens)` in `audioCache: [Int: SentenceAudio]`
- Tracked by `generationTask: Task<Void, Never>?`

**Playback (`playLoop()`, `@MainActor`):**
- Waits for `audioCache[currentSentenceIndex]` to be ready
- Calls `playerNode.scheduleBuffer(_:completionHandler:)`
- Awaits completion via `withCheckedContinuation`
- Advances `currentSentenceIndex`, saves progress
- Tracked by `playbackTask: Task<Void, Never>?`

Both tasks must be cancelled and nilled before starting new ones. `stop()` handles this.

**Word highlighting (Timer at 25Hz):**
- `bufferStartTime: Date` recorded at sentence start
- `elapsed = Date().timeIntervalSince(bufferStartTime) * Double(speed)`
- Finds `MToken` where `token.start_ts <= elapsed`
- Publishes `currentWordText` and `currentTokenIndex`
- When speed changes mid-sentence, `bufferStartTime` is recalibrated:
  `newStart = now - (elapsed_audio / newSpeed)`

### Content loading
```
loadURL(urlString) / loadPDF(url) / loadText(text)
    → load(from: ContentSource)
        → TextExtractor.extract()         // async throws
        → prepareText(body)               // splits into sentences
        → saveToPlaylist()                // inserts PlaylistItem via SwiftData
```

### Remote controls / Now Playing
`MPRemoteCommandCenter` — play, pause, togglePlayPause, skipForward, skipBackward.
`MPNowPlayingInfoCenter` — title, artist ("Pagehum"), playbackRate, elapsed/duration in sentence units.

---

## Text Extraction — `TextExtractor`

`@MainActor` class. Three paths:

### Web (URL)
1. Load URL in a hidden `WKWebView(frame: .zero)`
2. Wait for `didFinish` via `NavDelegate` with `withTaskCancellationHandler` — 20s timeout via `withThrowingTaskGroup`
3. 500ms settle delay for JS-rendered pages
4. Inject inline readability-style JS that:
   - Strips unlikely elements (nav, header, footer, ads, cookie banners) by class/id regex
   - Scores DOM nodes by text density, comma count, link density
   - Picks best content node (prefers `<article>` / `[role=main]` / `<main>` when content-rich)
   - Extracts: `title` (og:title → h1 → document.title), `textContent` (plain text), `byline`, `siteName`
5. Throws `URLError(.zeroByteResource)` if extracted text is empty
6. Returns `ReadingContent` with byline + siteName metadata

### PDF
- `Task.detached` with `PDFDocument` page iteration + `Task.checkCancellation()`
- Non-blocking — does not touch main thread

### Text
- Passthrough — wraps in `ReadingContent(title: "Pasted Text", body: text)`

---

## View Routing

```
HomeView
  ├── URL input  → load()  → WebReaderView   (source.webURL != nil)
  ├── PDF input  → load()  → ReaderView
  └── Text input → load()  → ReaderView

PlaylistView
  └── tap item   → reloadItem()  → WebReaderView (sourceType == "url")
                                 → ReaderView     (pdf / text)
```

Routing condition: `if let url = viewModel.content?.source.webURL { WebReaderView } else { ReaderView }`

---

## Views

### HomeView
Three-tab input (URL / File / PDF). URL tab has "Load Page" (navigate) and "Save for Later" (playlist only). File tab uses `.fileImporter` for PDFs.

### ReaderView
Used for PDF and pasted text. Sentence-by-sentence SwiftUI layout:
- `ScrollViewReader` auto-scrolls to `currentSentenceIndex` with `.easeInOut(0.5)` animation
- Each sentence is a `SentenceView` — tap to seek
- Active sentence has accent-color background tint
- Active sentence shows word highlighting (see below)
- Past sentences: `.secondary.opacity(0.55)`. Future: `.primary.opacity(0.8)`

**Word highlighting in `SentenceView`:**
- Receives `currentTokenIndex: Int` (position hint from TTS engine)
- `findActiveWordIndex()` searches ±2 words around `currentTokenIndex` for exact match (punctuation-stripped, lowercased)
- Falls back to forward scan from `currentTokenIndex`
- No fuzzy/substring matching — avoids highlighting "other" when word is "the"

### WebReaderView
Used for web articles. Shows the actual webpage in `WKWebView` (images, layout intact).
- `PlaybackControlsView` overlaid at bottom
- Sentence highlighting injected via JS: sets `backgroundColor: rgba(0,122,255,0.12)` + `borderRadius` on matching DOM element
- No auto-scroll — user scrolls manually
- JS receives sentence text JSON-encoded (never string-interpolated)
- `isReady` flag gates highlight calls until page + JS are loaded

### PlaybackControlsView
Floating card overlaid at bottom of both reader views.
- **Expanded**: progress bar (sentence count), back/play-pause/forward transport, speed label. Auto-collapses to minimized after 3s of playback.
- **Minimized**: play/pause + progress bar + speed + chevron. Tap to expand.
- Speed options: 0.75×, 1×, 1.25×, 1.5×, 2×, 2.5×, 3×

### PlaylistView
Three sections: Reading Queue (queued), In Progress, Completed. SwiftData `@Query` sorted by `dateAdded` descending. Per-item: progress bar, relative timestamp, source type badge. Swipe to delete.

### SettingsView
- **Playback**: speed picker (same 7 options as controls)
- **Reader**: text size slider 12–32pt with live serif preview
- **Voice**: navigation-link picker over all 28 voices with flag emoji + locale/gender label
- **Storage**: cached audio size + file count + "Clear Audio Cache" destructive button with confirmation dialog
- **About**: version, engine name, audio spec

---

## Offline Audio Cache — `AudioCacheManager`

Utility enum managing `Documents/AudioCache/`. Directory created lazily.

```swift
cacheDirectory: URL
totalSize() → Int64          // bytes
fileCount() → Int            // .m4a files
formattedSize() → String     // ByteCountFormatter
clearAll() throws            // deletes all files
```

No M4A files are written yet — infrastructure is ready for a future "pre-generate full article" feature.

---

## Voice System

28 voices loaded from `voices.npz` at startup. Voice key format: `"af_heart.npy"` (prefix `af` = American female, `bf` = British female, etc.). Language inferred from first char: `a`/`b` = English (US/GB), `j` = Japanese, `z` = Chinese, `e` = Spanish, `f` = French, `h` = Hindi, `i` = Italian, `p` = Portuguese.

When voice changes mid-playback: `audioCache` is cleared and `startPipeline()` restarts with new voice key.

---

## Persistence & Progress

Progress saved after every sentence via `saveProgressNow()`:
- Updates `PlaylistItem.progressPercent`, `lastSentenceIndex`, `lastPlayed`, `status`
- Calls `ctx.save()`

Resume: `prepareTextPublic(text, resumeAt: lastSentenceIndex)` seeks to saved position without playing.

`currentPlaylistItemID: PersistentIdentifier?` tracks which SwiftData item is active for progress writes.

---

## Background Playback

Fully functional. `UIBackgroundModes = audio` in project settings. AVAudioSession stays active. Lock screen / Control Center controls work via `MPRemoteCommandCenter`. Audio continues when screen locks or app is backgrounded.

---

## What's Not Yet Built

- **Pre-generated M4A files**: `AudioCacheManager` directory exists but no write path yet. Planned: generate entire article audio → AAC M4A → store in `Documents/AudioCache/<id>.m4a` with sentence timestamps for resume-with-seek.
- **Sentence timestamps in M4A**: For seeking within cached audio, needs a sidecar file mapping sentence index → byte offset.
