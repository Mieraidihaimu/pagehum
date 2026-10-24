# Local TTS research for Pagehum

Research date: 24 October 2026. Scope: offline English narration in the Swift iPhone/Mac app and Mac CLI. This is a source review, not a listening test or device benchmark.

The strongest candidate to evaluate for both size and quality is **Phonon 31m**. For the smallest download, evaluate **KittenTTS Nano int8 and Micro 0.8**. Keep **quantized Kokoro** as a control: changing the runtime may reduce the download without changing the voice family.

## Current baseline

`Pagehum/Speech/ModelStore.swift` specifies 327,115,152 bytes of Kokoro weights and 14,629,684 bytes of voice data: **341,744,836 bytes, or 341.7 MB decimal**. `Packages/SpeechCore/Package.swift` uses `mlalma/kokoro-ios` and MLX. `KokoroSpeechEngine` returns sentence audio and word timings. The app's speech format is mono Float32 at 24 kHz.

The existing `SpeechEngine` interface makes experiments possible without replacing playback. GPU lifecycle management, model downloading, voice identifiers, and cache identity still contain Kokoro-specific assumptions.

## Shortlist

Sizes below describe the named weights or archive, not total installed app size, runtime memory, or the complete dependency download.

| Candidate | Published size | Integration | Assessment |
| --- | --- | --- | --- |
| Phonon 31m English | 64.5 MB q8 GGUF weights; the v0.4.0 Core ML archive is listed as 131 MB by GitHub | Official Swift `ptts` package, module `PhononTTS`; also Rust/C/Python/CLI | Best lead for smaller size and improved naturalness; very new |
| KittenTTS Nano 0.8 int8 | About 25 MB; 15M parameters | First-party Swift SDK using ONNX Runtime | Strong size candidate; quality improvement over Kokoro is unproven |
| KittenTTS Micro 0.8 | About 40–41 MB; 40M parameters | Same SDK | Include alongside Nano in the quality/size comparison |
| Kokoro v1.0 ONNX | 86 MB `model_q8f16.onnx`, or 92.4 MB `model_quantized.onnx`, plus voices/front end | ONNX Runtime or a supported sherpa-onnx model export | Smaller version of the existing model family; no inherent quality upgrade |
| Pocket TTS small English | 18.2M, 6.9M, or experimental 1.9M parameters, including decoder; deployment bytes not verified | Official Python and standalone Rust CLI; mobile export compatibility needs verification | Worth a separate experiment; parameter count alone does not establish app footprint or quality |

Primary size sources: [Phonon model card](https://huggingface.co/gradium/phonon-31m-en), [Phonon release assets](https://github.com/gradium-ai/xn-ptts/releases), [Kitten Nano model](https://huggingface.co/KittenML/kitten-tts-nano-0.8-int8), [Kitten Micro model](https://huggingface.co/KittenML/kitten-tts-micro-0.8), [Kokoro ONNX files](https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/tree/main/onnx), and [Pocket TTS repository](https://github.com/kyutai-labs/pocket-tts).

## What supports the quality recommendation

Gradium released the open Phonon family on **20 October 2026**. Its publisher-run blind listening evaluation reports English preference Elo of **2098 for Phonon 31m**, **2043 for Kokoro**, and **2056 for Pocket TTS 100m**. These are encouraging vendor results, not an independent replication or proof of better long-form narration. Voice selection and text normalization affect comparisons. [Gradium release and evaluation](https://gradium.ai/blog/release-phonon-open-weight).

Phonon 31m's weights are Apache-2.0. The 40m and multilingual variants have **CC BY-NC 4.0** weights; they should not be treated as equivalent options for a commercial release. [Model licenses](https://huggingface.co/gradium/phonon-31m-en).

Kitten's small 0.8 models are distinct from its newer **KittenTTS 2**, a 1.7B model listed at 506 MiB. The larger product's cloning and expression claims do not establish the small models' quality. [Kitten model families](https://github.com/KittenML/KittenTTS).

Pocket's small models also arrived on 20 October. Version 4.0.1 on 21 October fixed pronunciation issues affecting the sub-20M models, including the default demo sentence. This is a reason to pin a corrected version and test difficult text. The 1.9M pair is explicitly experimental. [Pocket releases](https://github.com/kyutai-labs/pocket-tts/releases). Its code is MIT and the published model repository identifies the weights as CC BY 4.0; voice licenses must also be checked. [Pocket model card](https://huggingface.co/kyutai/pocket-tts).

## SDK and deployment details

**Phonon:** the official Swift package requires iOS 18/macOS 15 on Apple silicon, fitting Pagehum's deployment targets. It uses Core ML and streams 24 kHz PCM. The Swift guide reports roughly 95 MB synthesis memory, about 10 seconds for initial device compilation, and about 0.6 seconds for later loads. Installed models can take roughly twice the model folder's space because compiled copies are retained. Its example iPhone 16 Pro measurements are 12–14.5x real time on the Neural Engine and 10x on CPU, with first audio in tens of milliseconds. These are upstream figures, not Pagehum measurements, and the main README reports different benchmark figures. [Swift integration guide](https://github.com/gradium-ai/xn-ptts/blob/main/ios/PhononTTS/README.md).

The public Swift API supports selecting CPU or Neural Engine execution, cancellation, full synthesis, and streaming. I found no word timestamp output in that API. [Swift implementation](https://github.com/gradium-ai/xn-ptts/blob/main/ios/PhononTTS/Sources/PhononTTS/Phonon.swift).

**Kitten:** its Swift SDK supports iOS 16/macOS 14, eight voices, and raw 24 kHz samples. The default phonemizer downloads GPLv3 rule/dictionary files; the SDK also allows a custom phonemizer. That dependency needs its own distribution review. Its documented result type has no word timing fields. [Kitten Swift SDK](https://github.com/KittenML/KittenTTS-swift). Its package adds Microsoft's ONNX Runtime Swift dependency, so the 25 MB weights are not the entire SDK footprint. [Package manifest](https://github.com/KittenML/KittenTTS-swift/blob/main/Package.swift).

**sherpa-onnx:** useful if a shared C/Swift runtime for several engines is desirable. Its documentation covers Kokoro, Kitten, Pocket, Supertonic, and Piper. Verify the exact exported model/version rather than assuming arbitrary ONNX files are interchangeable. [TTS documentation](https://k2-fsa.github.io/sherpa/onnx/tts/index.html), [Swift bindings and platforms](https://github.com/k2-fsa/sherpa-onnx).

**Supertonic:** has Swift/iOS examples and multilingual ONNX models, but the upstream repository was archived on **9 September 2026** and states development and support have ended. I would not prioritize a new Pagehum dependency on it. [Upstream archive notice](https://github.com/supertone-oss-archive/supertonic).

## Implications for Pagehum

1. Add an experimental engine behind `SpeechEngine`. Start with full-sentence synthesis; the current interface cannot expose a backend's first-chunk streaming latency directly.
2. Preserve 24 kHz mono output and existing playback speed handling. Phonon and Kitten already document compatible PCM formats.
3. Plan word highlighting explicitly. Phonon and Kitten's inspected APIs do not supply Kokoro-equivalent timings. Pagehum already has estimated timings in `SystemSpeechEngine`; exact alignment would require additional work and possibly another model.
4. Change cache identity to include engine, model revision, normalization version, and voice. `AudioDiskCache` currently hardcodes `kokoro-v1_0`, and the generation path appends `.npy` to voice identifiers.
5. Make background synthesis capability explicit. `ReaderModel` currently gates synthesis for the MLX lifecycle. CPU execution avoids that GPU dependency, but sustained iPhone lock-screen generation, audio session behavior, heat, and battery use still require physical-device validation. Neural Engine speed alone does not prove background suitability.
6. Extend verified asset downloading for the chosen engine and measure final Release download/install size. Do not substitute the 64.5 MB GGUF figure for the larger Core ML deployment.

## Recommended experiment

Compare existing Kokoro, Phonon 31m, Kitten Micro 0.8, Kitten Nano int8, and one quantized Kokoro export. Keep Pocket small as a follow-up unless its exact iOS deployment is verified first.

Use the same 30 passages: ordinary articles, long paragraphs, British and American proper names, dates, money, percentages, abbreviations, URLs, technical terms, and code-adjacent prose. Include a full 20-minute article. Compare matched loudness and both 1x and 1.5x playback. Test raw input and equivalent text normalization so preprocessing advantages are visible.

Record blind listening preference, omissions/repetitions/mispronunciations, download bytes, installed bytes, peak memory, cold and warm startup, full-sentence latency, first-chunk latency where available, synthesis speed, and energy/thermal behavior. Test airplane mode, cancellation/seek, interruptions, and screen lock on the oldest supported physical iPhone plus an Apple silicon Mac.

Choose Phonon if it wins listening preference and passes lifecycle/timing requirements. Choose Kitten if footprint is the priority and its listening result is acceptable. Choose quantized Kokoro if it preserves the preferred sound with an acceptable size and runtime tradeoff. No winner has been established by local testing yet.
