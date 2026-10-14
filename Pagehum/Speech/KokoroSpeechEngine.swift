import AVFoundation
import SpeechCore

/// Adapts `KokoroSynthesizer` to `SpeechEngine`. MLX work stays on a global dispatch queue:
/// it blocks internally and deadlocks on Swift concurrency's cooperative pool.
final class KokoroSpeechEngine: SpeechEngine {
    let voices: [String]
    private let synthesizer: KokoroSynthesizer

    private init(synthesizer: KokoroSynthesizer) {
        self.synthesizer = synthesizer
        voices = synthesizer.voices
    }

    static func load(directory: URL) async throws -> KokoroSpeechEngine {
        let synthesizer = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result {
                    try KokoroSynthesizer.load(directory: directory,
                                               gpuCacheLimit: 512 * 1024 * 1024,
                                               gpuMemoryLimit: 2048 * 1024 * 1024)
                })
            }
        }
        return KokoroSpeechEngine(synthesizer: synthesizer)
    }

    func synthesize(_ text: String, voice: String, format: AVAudioFormat) async -> SentenceAudio? {
        let synthesizer = self.synthesizer
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let generated = try synthesizer.generate(text: text, voice: voice, format: format)
                    let timings = generated.words.map { WordTiming(text: $0.text, start: $0.start, end: $0.end) }
                    continuation.resume(returning: SentenceAudio(buffer: generated.buffer, tokens: timings.isEmpty ? nil : timings))
                } catch {
                    print("Kokoro error: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
