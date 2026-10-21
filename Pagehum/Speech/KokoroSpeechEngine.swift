import AVFoundation
import SpeechCore

/// Adapts `KokoroSynthesizer` to `SpeechEngine`. MLX work stays on a serial dispatch queue:
/// it blocks internally and deadlocks on Swift concurrency's cooperative pool.
final class KokoroSpeechEngine: SpeechEngine {
    private static let workQueue = SpeechSynthesisWorkQueue()
    let voices: [String]
    private let synthesizer: KokoroSynthesizer

    private init(synthesizer: KokoroSynthesizer) {
        self.synthesizer = synthesizer
        voices = synthesizer.voices
    }

    static func load(directory: URL) async throws -> KokoroSpeechEngine {
        let synthesizer = try await workQueue.perform {
            try KokoroSynthesizer.load(directory: directory,
                                       gpuCacheLimit: 512 * 1024 * 1024,
                                       gpuMemoryLimit: 2048 * 1024 * 1024)
        }
        return KokoroSpeechEngine(synthesizer: synthesizer)
    }

    func synthesize(_ text: String, voice: String, format: AVAudioFormat) async -> SentenceAudio? {
        let synthesizer = self.synthesizer
        do {
            return try await Self.workQueue.perform {
                let generated = try synthesizer.generate(text: text, voice: voice, format: format)
                let timings = generated.words.map { WordTiming(text: $0.text, start: $0.start, end: $0.end) }
                return SentenceAudio(buffer: generated.buffer, tokens: timings.isEmpty ? nil : timings)
            }
        } catch {
            print("Kokoro error: \(error)")
            return nil
        }
    }

    /// Synchronously flushes in-flight Metal command buffers and evicts idle heap caches
    /// to satisfy iOS background Jetsam limits and prevent SIGABRT watchdog termination.
    static func drainAndEvictGPU() {
        workQueue.suspendAndDrain {
            KokoroSynthesizer.synchronizeGPU()
            KokoroSynthesizer.clearGPUCache()
        }
    }

    static func resumeGPUWork() {
        workQueue.resume()
    }
}

/// MLX stream access, including cleanup, must stay on one queue. The synchronous
/// suspension barrier finishes current inference before iOS can suspend the app.
nonisolated final class SpeechSynthesisWorkQueue: @unchecked Sendable {
    enum WorkError: Error { case suspended }

    private let queue = DispatchQueue(label: "com.pagehum.speech-synthesis", qos: .userInitiated)
    private var isSuspended = false
    private var hasPerformedWork = false

    func perform<Value>(_ operation: @escaping () throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard !self.isSuspended else {
                    continuation.resume(throwing: WorkError.suspended)
                    return
                }
                self.hasPerformedWork = true
                continuation.resume(with: Result { try operation() })
            }
        }
    }

    func suspendAndDrain(_ drain: () -> Void) {
        queue.sync {
            isSuspended = true
            // System-voice sessions, including the simulator, never initialize MLX.
            if hasPerformedWork { drain() }
        }
    }

    func resume() {
        queue.sync { isSuspended = false }
    }
}
