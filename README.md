<div align="center">

# Pagehum

**Your reading list, read aloud.**

A native reader for Mac and iPhone, with local speech generation and a Mac command line.

[![SwiftUI](https://img.shields.io/badge/Built_with-SwiftUI-blue)](#build-the-app)
[![Kokoro + MLX](https://img.shields.io/badge/Speech-Kokoro_%2B_MLX-purple)](#how-it-works)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-green.svg)](LICENSE)

[Download CLI](https://github.com/Mieraidihaimu/pagehum/releases/tag/v0.1.0) · [Get started](#get-started) · [CLI guide](docs/CLI.md) · [Contribute](CONTRIBUTING.md)

</div>

Turn articles, PDFs, and pasted text into a listening library. Follow along while Pagehum reads, queue up your next article, or export narration from the terminal as M4A or WAV.

Speech is generated on your device using **Kokoro and Apple's MLX framework**. No speech API key or cloud TTS service is required. Web imports and Hacker News discovery use the network; downloaded text and model assets can be used for local synthesis.

[Listen to a short Pagehum voice sample](https://github.com/Mieraidihaimu/pagehum/releases/download/v0.1.0/pagehum-sample.m4a).

## What you can do

- **Listen to your reading list.** Import a web article, PDF, or pasted text into the app.
- **Read along.** Use the reader, playback controls, and text highlighting.
- **Keep a library and queue.** Search saved content and choose what plays next.
- **Discover tech articles.** Import Hacker News links using topic, age, and score filters.
- **Export audio from your Mac.** Feed the CLI text, a file, stdin, or an article URL; get M4A or WAV.
- **Choose English voices.** The CLI supports American and British English voice styles and lists them with `pagehum voices`.

## Get started

The first public version is an **early prerelease**. [Download the Apple Silicon CLI](https://github.com/Mieraidihaimu/pagehum/releases/tag/v0.1.0), or build the app and CLI from source below. The CLI archive includes the model assets and is not notarized. There is no signed app installer or App Store release yet.

After extracting the CLI archive, open its `pagehum` directory in Terminal and run `./pagehum --help`. Keep the whole directory together. If macOS blocks this unsigned prerelease, build from source. A SHA-256 checksum file accompanies the download.

| Component | Requirements |
| --- | --- |
| macOS app and CLI | Apple Silicon, macOS 15.6+, Xcode 26.1+ with the Metal toolchain |
| iOS app | Physical device with MLX support; app target is iOS 18.6+ |
| Bundled iOS share extension | Currently targets iOS 26.1; use iOS 26.1+ for the full app and extension build |

MLX speech generation does not run in the iOS Simulator. The iOS distribution build has not yet been validated for this source release.

```sh
git clone https://github.com/Mieraidihaimu/pagehum.git
cd pagehum
./scripts/download-models.sh
```

The setup script downloads approximately **342 MB** of model and voice assets from a pinned upstream revision and verifies their SHA-256 checksums. Assets stay local and are excluded from Git. Git LFS is not required to clone Pagehum.

### Build the app

```sh
open Pagehum.xcodeproj
```

Select **Pagehum-macOS** or **Pagehum-iOS**. For device builds, choose your development team and configure your own app identifiers and shared app group in both the app and extension. The checked-in identifiers are retained for compatibility with existing development installations; the project does not include signing credentials.

### Use the command line

```sh
./scripts/build-cli.sh
export PATH="$PWD/.build/pagehum-cli:$PATH"

pagehum voices
pagehum generate --text "Your reading list, read aloud." -o hello.m4a
pagehum generate --file notes.txt --quality high -o notes.m4a
pagehum generate --url "https://example.com/article" -o article.m4a
pbpaste | pagehum generate --stdin -o clipboard.wav
```

The default export is 24 kHz mono AAC at a target 48 kbps. Compact and high quality presets use 32 and 64 kbps; WAV exports 16-bit PCM. Keep the entire `.build/pagehum-cli` directory together when moving the tool: its model bundle, package resources, and frameworks are required.

See the [CLI guide](docs/CLI.md) for all options and verification commands.

## How it works

```text
Article URL / PDF / text           Text / file / stdin / URL
           │                                 │
     Native SwiftUI reader              pagehum CLI
           │                                 │
           └────────── SpeechCore ────────────┘
                            │
                       Kokoro + MLX
                            │
                  Local playback / audio export
```

`Pagehum/` contains the app and reader, `PagehumCLI/` contains export commands, and `SpeechCore/` shares model loading and sentence synthesis between them. `PagehumShare/` handles iOS sharing.

## Current limits

- Web extraction can fail on dynamic, blocked, or non-article pages. It does not bypass login or paywalls.
- Hacker News discovery runs on request; there is no scheduled background import.
- English is the supported CLI language set. Voice quality and pronunciation depend on the model and input.
- This is an early project. See [contribution and test notes](CONTRIBUTING.md) before working on playback or packaging.

## Contributing

Bug reports, reader improvements, accessibility work, and reproducible playback fixes are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md), or [open an issue](https://github.com/Mieraidihaimu/pagehum/issues) describing what you tried and what happened.

If Pagehum helps you get through your reading list, a star helps others discover it.

## Credits and license

Pagehum builds on [mlalma/KokoroTestApp](https://github.com/mlalma/KokoroTestApp). It extends that foundation with a reading library, article extraction, listening queues, a desktop interface, and CLI audio export.

Thanks to [Kokoro](https://huggingface.co/hexgrad/Kokoro-82M), [Kokoro iOS](https://github.com/mlalma/kokoro-ios), [MLX Swift](https://github.com/ml-explore/mlx-swift), [MisakiSwift](https://github.com/mlalma/MisakiSwift), [MLXUtilsLibrary](https://github.com/mlalma/MLXUtilsLibrary), and [Swift Argument Parser](https://github.com/apple/swift-argument-parser). The reader includes Mozilla Readability and DOMPurify with their license files.

Pagehum source is licensed under [Apache-2.0](LICENSE). See [NOTICE](NOTICE) for provenance; dependencies and model assets retain their respective licenses.
