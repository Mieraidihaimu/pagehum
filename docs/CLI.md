# Pagehum for macOS

`pagehum` generates local Kokoro narration from text, a UTF-8 file, standard input, or a web article. It supports American and British English voices on Apple Silicon, macOS 15.6 or later. Speech synthesis runs locally; URL input fetches the page and its resources over the network.

## Download

The [v0.1.0 prerelease](https://github.com/Mieraidihaimu/pagehum/releases/tag/v0.1.0) includes `pagehum-0.1.0-macOS-arm64.tar.gz` and its SHA-256 checksum. Extract it, keep the entire `pagehum/` directory together, and run `./pagehum --help` from that directory. The archive includes model assets and dependency resources. This is an unsigned, unnotarized prerelease; build from source if macOS blocks it.

## Build and run

Build with Xcode 26.1 or newer and its Metal toolchain installed. Run `./scripts/download-models.sh` first to download and verify the model and voice assets.

```bash
./scripts/build-cli.sh
./.build/pagehum-cli/pagehum --help
./.build/pagehum-cli/pagehum voices
./.build/pagehum-cli/pagehum generate --text "Hello from your Mac." -o hello.m4a
./.build/pagehum-cli/pagehum generate --file notes.txt --quality high -o notes.m4a
./.build/pagehum-cli/pagehum generate --url "https://example.com/article" -o article.m4a
pbpaste | ./.build/pagehum-cli/pagehum generate --stdin -o clipboard.wav
```

Alternatively, select the shared **pagehum** scheme in Xcode. Set the scheme's launch arguments to a command such as `generate --text "Hello" -o /tmp/hello.m4a`.

The build script produces `.build/pagehum-cli/`, containing the executable, model/reader bundle, Swift package resource bundles, and dynamic frameworks. Keep the entire directory together when moving it; copying just the executable is insufficient. `PAGEHUM_BUILD_DIR` overrides the derived data directory and `CONFIGURATION=Debug` selects a debug build. Release is the default.

To make it available in your current shell, from the repository root:

```bash
export PATH="$PWD/.build/pagehum-cli:$PATH"
pagehum generate --text "Ready to speak." -o ready.m4a
```

This is a local build, not a notarized distribution. Building does not install anything into a system directory.

## Inputs and options

Choose exactly one of `--text`, `--file`, `--stdin`, or `--url`. Files and stdin must contain UTF-8 text. The destination directory must already exist. The output extension selects the format: `.m4a` or `.wav`.

- `--voice af_heart`: default voice. `pagehum voices` lists available English voices. Names beginning with `b` select British English pronunciation; names beginning with `a` select American English.
- `--quality compact|balanced|high`: M4A encoding preset; balanced is the default.
- `--force`: replace an existing output only after successful generation. Existing files are protected by default.
- `--model-dir /path/to/assets`: directory containing `kokoro-v1_0.safetensors` and `voices.npz`. Also configurable through `PAGEHUM_MODEL_DIR`; the explicit option takes precedence. By default, use the bundled assets beside the executable. URL extraction still requires the reader scripts in that bundle.

Progress and model diagnostics go to stderr. Successful generation prints the absolute output pathname to stdout. Errors return a nonzero exit status. Generation failures identify the failing chunk and do not publish partial narration. An interrupted process can leave a hidden `.pagehum-<UUID>.m4a` or `.wav` temporary file in the destination directory, which can be removed after the process exits.

## Audio quality and size

| Preset | Encoding | Approximate audio payload per hour |
| --- | --- | ---: |
| compact | AAC, 32 kbps, M4A | 14.4 MB |
| balanced | AAC, 48 kbps, M4A | 21.6 MB |
| high | AAC, 64 kbps, M4A | 28.8 MB |
| WAV | PCM, 16-bit | 172.8 MB |

Apple’s AAC encoder supports up to 64 kbps at 24 kHz mono on the tested Mac. The presets use 32/48/64 kbps to preserve the native rate without resampling.

All formats preserve Kokoro's native 24 kHz mono output. Bitrate is a target; actual bitrate and container overhead vary, especially for very short clips. The M4A preset does not affect WAV output.

The exporter uses fresh PCM from Kokoro and feeds successive chunks to one encoder. It does not transcode the app's 32 kbps sentence cache. Higher bitrates preserve more of the generated signal; they do not change the underlying voice model, pronunciation, or prosody. These are initial presets to compare by listening.

URL extraction reuses the app's WebKit/Readability pipeline and requires a normal logged-in macOS session. It does not use browser cookies or bypass authentication/paywalls. Some dynamic, blocked, or non-article pages may fail extraction. Navigation has a 20-second timeout; the full extraction is capped at 60 seconds. Plain text input is useful for pages that cannot be extracted.

## Implementation

- `Packages/SpeechCore`: local Swift package shared by the app and CLI, containing model loading, synthesis (`KokoroSynthesizer`), and sentence segmentation. It is the only module that imports Kokoro or MLX. Model work runs on GCD, avoiding MLX work on Swift's cooperative executor.
- `PagehumCLI/`: Argument Parser commands and the streaming audio exporter.
- The CLI also compiles the existing reader document/extraction sources, with its own resource bundle.
- The app retains its playback/cache behavior and reaches Kokoro through its `SpeechEngine` adapter.

## Verification

```bash
python3 scripts/test-cli.py .build/pagehum-cli/pagehum
xcodebuild -project Pagehum.xcodeproj -scheme Pagehum-macOS \
  -destination 'platform=macOS,arch=arm64' test \
  -only-testing:PagehumTests/SentenceSegmenterTests \
  -only-testing:PagehumTests/ArticleSegmenterOffsetTests \
  -only-testing:PagehumTests/ReaderDocumentProjectionTests
```

The smoke test runs real synthesis, checks WAV properties and AAC presets, verifies stdout/error/overwrite behavior, and serves a local HTML article to exercise URL extraction. Run it with GPU and WebKit access, outside a restricted execution sandbox.

Initial verification on the development Mac passed the CLI smoke test, the relocated-package check (with the original Release build directory unavailable), and all nine tests in the three suites above. Two existing playback-state tests, `transitionsFromPreparingThroughAudiblePausedAndFinished` and `allGenerationFailuresRemainIncompleteAndReportEverySentence`, failed both with these changes and in a separate copy of the original code.

## Packaging

After building, run `./scripts/package-cli.sh`. It creates a versioned Apple Silicon archive and checksum in `.build/releases/`, including model assets, framework resources, and license notices. See [release notes](RELEASE_NOTES.md) for launch verification.
