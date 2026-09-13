# Naming and GitHub launch proposal

Status: accepted naming proposal. The Pagehum rename is implemented; see RELEASE_NOTES.md for publication and validation details. The findings below record the pre-launch audit.

## Recommended identity

**Pagehum** — **Your reading list, read aloud.**

The name connects pages with sound, is short enough for a command, and can cover both the reader app and audio exports. Keep Kokoro visible as the speech engine in the description and acknowledgments.

Proposed GitHub description:

> Turn articles, PDFs, and text into natural speech on your Mac and iPhone. Local Kokoro TTS, a native SwiftUI reader, and a macOS CLI.

Proposed README opening:

> # Pagehum
> Your reading list, read aloud.
>
> Listen to articles, PDFs, and pasted text with speech generated on your device. Save reading to your library, follow along during playback, or use the Mac command line to export narration as M4A or WAV.
>
> Built with SwiftUI, Kokoro, and MLX for Apple Silicon. Speech generation runs locally; importing web articles and discovering Hacker News links use the network.

## One naming system

| Surface | Proposed name |
| --- | --- |
| App and README title | Pagehum |
| GitHub repository | `Mieraidihaimu/pagehum` |
| Xcode project | `Pagehum.xcodeproj` |
| App target and source folder | `Pagehum` |
| Shared schemes | `Pagehum-macOS`, `Pagehum-iOS`, `pagehum` |
| App entry point | `PagehumApp.swift` / `PagehumApp` |
| Main observable model | `ReaderModel.swift` / `ReaderModel` |
| Tests | `PagehumTests` |
| Share extension target | `PagehumShare` |
| Share menu label | Add to Pagehum |
| CLI target and command | `pagehum` |
| CLI source folder | `PagehumCLI` |
| Shared synthesis sources | `SpeechCore` (descriptive internal name) |
| CLI resource bundle | `pagehum-resources.bundle` |
| Environment variables | `PAGEHUM_BUILD_DIR`, `PAGEHUM_MODEL_DIR` |
| macOS app artifact | `Pagehum-<version>-macOS-arm64.zip` |
| CLI artifact | `pagehum-<version>-macOS-arm64.tar.gz` |

Example after implementation:

```sh
pagehum generate --url "https://example.com/article" -o article.m4a
pbpaste | pagehum generate --stdin -o notes.wav
```

Update scripts, scheme references, test imports, resource lookup, UI strings, and CLI documentation together. Preserve model asset names and third-party attribution. Keep existing bundle identifiers, app groups, saved-data keys, and legacy URL handling during the initial rename so existing installations retain access to their libraries. Add a new URL scheme only with verified registration and share-extension handling.

## Name research

Checked on 2026-09-13. Exact-name web and GitHub-indexed searches did not surface a Pagehum reader or TTS project, but [Pagehum is used as a music artist name](https://audiomack.com/pagehum). This is a candidate, not an assertion of exclusive name availability. The authenticated account's repository listing has no `pagehum` repository.

The existing Speechly name overlaps with [an established voice technology company](https://www.ycombinator.com/companies/speechly). A distinct project name should make the app easier to identify in searches.

## Launch presentation

1. Open the README with the benefit, a real app screenshot, and a short recording that demonstrates article import, playback, and reading progress. Use a short original sample article and narration clip.
2. Put a working quick start immediately below the demo. Include actual OS requirements, model setup, and one copyable CLI command.
3. Explain the useful differences: speech generated locally, native Mac/iPhone reading, saved library and queue, PDF/text/article input, and scriptable audio export.
4. Provide a tested Mac release when packaging is ready. Include all CLI resource bundles and frameworks. State signing/notarization status accurately.
5. Add contribution instructions, useful issue templates, and a small roadmap tied to real limitations. Preserve the Apache-2.0 license and credit the upstream KokoroTestApp, Kokoro, MLX, Misaki, Readability, and DOMPurify projects.
6. Use relevant GitHub topics: `text-to-speech`, `kokoro`, `mlx`, `swiftui`, `macos`, `ios`, `reader`, `cli`, `local-ai`.
7. Draft an honest launch post around the working demo and an explicit invitation for feedback. Posting to communities is a separate step that requires the user's authorization to send those messages.

The aim is to make the project easy to understand, try, and recommend. Stars cannot be guaranteed.

## Findings to resolve before publication

- GitHub authentication works outside the network sandbox as `Mieraidihaimu`. This checkout has no Git remote.
- The working tree contains existing CLI and shared-synthesis changes. Preserve and include those deliberately during release preparation.
- `Resources/kokoro-v1_0.safetensors` is a 327,115,152-byte ordinary Git blob, despite the README describing LFS. [GitHub blocks ordinary Git files over 100 MiB](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github). A deletion commit alone will not remove the oversized object from history.
- Recommended distribution: a small source repository with a pinned, checksum-verified asset download step. Prepare publication in a separate staging copy so local history and model assets remain recoverable; preserve upstream attribution. Alternatively, migrate the publication copy's history to LFS.
- Remove tracked `.DS_Store`, personal `xcuserdata`, and scratch `File.txt` from the publication copy. Expand `.gitignore`; its current content only excludes `.build/`.
- App settings specify iOS 18.6 and macOS 15.6, while the share extension specifies iOS 26.1. Resolve or document the effective iOS requirement after a device/archive build; do not advertise the README's current iOS 18.0 / macOS 15.0 requirements.
- The app icon asset catalog contains slots but no image files. Add a finished app icon before distributing an app build.
- `docs/CLI.md` reports two existing playback-state test failures. Reproduce and resolve them or clearly document them for a prerelease. Validate app and CLI builds after renaming, run relevant tests, and verify the exported CLI works from a relocated directory.

## Publication sequence

Choose the name, apply the coherent rename, finish the README/demo and asset setup, validate the build and packaging, then create the public repository and push the prepared source. Publish a versioned prerelease only after testing its actual artifacts. The implementation and publication results are recorded in RELEASE_NOTES.md.
