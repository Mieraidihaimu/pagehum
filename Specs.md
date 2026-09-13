# Specs.md — Pagehum Product Specification

## Overview

Pagehum is an on-device text-to-speech reader for iOS. It converts web articles, PDFs, and pasted text into natural spoken audio using the Kokoro 82M neural TTS model running locally via MLX. No server, no API calls, fully offline after model load.

## Target Platform

- iOS 18.6+
- Physical devices only (MLX requires Apple Neural Engine / GPU — no Simulator)
- iPhone and iPad

## Core Features

### 1. Content Input

| Source | Entry Point | Extraction |
|--------|-------------|------------|
| Web URL | Home screen URL field | Readability-style JS in headless WKWebView |
| PDF file | Home screen file picker | PDFKit page-by-page text extraction |
| Pasted text | Home screen text editor | Direct passthrough |
| Shared URL | Safari Share Sheet → Extension | App group UserDefaults + deep link |

### 2. Text-to-Speech Playback

- **Model**: Kokoro 82M (safetensors, ~600MB bundled via Git LFS)
- **Audio format**: 24 kHz, mono, Float32 PCM
- **Latency**: First sentence plays after ~1-2s generation; subsequent sentences are pre-generated 3 ahead
- **Speed control**: 0.75x, 1x, 1.25x, 1.5x, 2x, 2.5x, 3x via AVAudioUnitTimePitch
- **Background audio**: Continues playing with screen off or app backgrounded
- **Lock screen controls**: Play/pause, skip forward/backward via MPRemoteCommandCenter
- **Word-level highlighting**: Real-time highlight of current spoken word in ReaderView

### 3. Reading Views

**ReaderView** (PDF / text sources):
- Sentence-by-sentence display in scrollable LazyVStack
- Current sentence highlighted with accent color background
- Current word underlined and bolded during playback
- Tap any sentence to seek
- Auto-scrolls to current sentence

**WebReaderView** (URL sources):
- Full WKWebView showing the original webpage
- Current sentence highlighted with blue overlay via injected JS
- Playback controls overlaid at bottom

### 4. Library / Playlist

- Articles automatically saved on load with full extracted text
- Three sections: Reading Queue, In Progress, Completed
- Resume from last sentence position
- Progress bar showing percent complete
- Swipe to delete

### 5. Voice Selection

- Multiple voices bundled in `voices.npz`
- Naming convention: `{lang}{gender}_{name}` (e.g., `af_heart` = American Female "Heart")
- Supported languages: US English, UK English, Japanese, Chinese, Spanish, French, Hindi, Italian, Portuguese
- Voice change mid-playback restarts generation with new voice

### 6. Settings

- Playback speed (persisted to UserDefaults)
- Reader text size (12–32pt, serif font)
- Voice picker with language flags
- Audio cache management (size display, clear action)

### 7. Share Extension

- Appears in Safari's Share Sheet as "Pagehum"
- Passes URL to main app via app group (`group.com.test.mier.hello`)
- Opens app and begins loading the shared URL

## Performance Requirements

- App launch must not block main thread (model loads asynchronously)
- Navigation between views must be responsive (LazyVStack, no heavy arrays in UIViewRepresentable)
- Audio generation runs on GCD background queue (not Swift concurrency cooperative pool)
- WKWebView must not compete with pipeline for main actor time

## Data Model

### PlaylistItem (SwiftData)

| Field | Type | Purpose |
|-------|------|---------|
| title | String | Article title |
| sourceURL | String? | Original URL (for web sources) |
| sourceType | String | "url", "pdf", or "text" |
| textPreview | String | First 200 chars for list display |
| fullText | String | Complete extracted text for offline replay |
| dateAdded | Date | When item was saved |
| lastPlayed | Date | Last interaction timestamp |
| progressPercent | Double | 0.0–1.0 playback progress |
| lastSentenceIndex | Int | Resume position |
| status | String | "queued", "inProgress", "completed" |

## Known Constraints

- **Sentence length**: Kokoro has a token limit (~510 tokens). Sentences over 400 characters are auto-split at clause boundaries. If splitting still exceeds the limit, the sentence is skipped.
- **First launch**: Model loading takes several seconds. UI shows "Loading model…" indicator.
- **Memory**: The model consumes ~512MB GPU cache + working memory. MLX memory limits are set at 2GB.
- **No Simulator**: All testing must happen on physical device.
- **No unit tests**: The project has no test target. Validation is manual.

## URL Scheme

```
pagehum://open?url=<encoded-url>
```

Used by the Share Extension to hand off URLs to the main app.

## Bundle Configuration

| Key | Value |
|-----|-------|
| Main bundle ID | `com.test.mier.hello` |
| Share Extension bundle ID | `com.test.mier.hello.PagehumShare` |
| App Group | `group.com.test.mier.hello` |
| URL Scheme | `pagehum` |
| Background Modes | `audio` |

## Future / Planned

- Offline audio cache: pre-generate and save M4A files for full offline replay (AudioCacheManager directory exists, not yet wired to generation)
- Streaming generation: play audio as it generates instead of waiting for full sentence
- Multi-language auto-detection per sentence
