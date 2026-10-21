// Modified for Pagehum: unified application and command-line naming.
import AVFoundation
import Foundation
import KokoroSwift
import MLX
import MLXUtilsLibrary
import Metal

public enum SpeechSynthesisError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

/// A spoken word with timestamps in seconds at speed 1.0.
public struct SpokenWord: Sendable {
    public let text: String
    public let start: Double?
    public let end: Double?
}

/// The only type that touches Kokoro or MLX. Synchronous boundary: call only on a dedicated
/// dispatch queue, never the cooperative executor, because MLX performs blocking dispatch internally.
public final class KokoroSynthesizer: @unchecked Sendable {
    public static let sampleRate = Double(KokoroTTS.Constants.samplingRate)

    /// Voice names without the `.npy` suffix, e.g. "af_heart".
    public let voices: [String]
    private let engine: KokoroTTS
    private let styles: [String: MLXArray]

    private init(engine: KokoroTTS, styles: [String: MLXArray]) {
        self.engine = engine
        self.styles = styles
        voices = styles.keys.map { String($0.split(separator: ".")[0]) }.sorted()
    }

    public static func load(directory: URL, gpuCacheLimit: Int? = nil, gpuMemoryLimit: Int? = nil) throws -> KokoroSynthesizer {
        let model = directory.appendingPathComponent("kokoro-v1_0.safetensors")
        let voicesFile = directory.appendingPathComponent("voices.npz")
        for file in [model, voicesFile] {
            guard FileManager.default.isReadableFile(atPath: file.path) else {
                throw SpeechSynthesisError.message("Missing resource: \(file.path)")
            }
            let handle = try FileHandle(forReadingFrom: file)
            let prefix = try handle.read(upToCount: 128) ?? Data()
            try handle.close()
            if String(data: prefix, encoding: .utf8)?.hasPrefix("version https://git-lfs") == true {
                throw SpeechSynthesisError.message("\(file.lastPathComponent) is a Git LFS pointer. Download the model assets first.")
            }
        }
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw SpeechSynthesisError.message("No Metal GPU is available. Run pagehum on an Apple Silicon Mac with GPU access.")
        }
        guard let styles = NpyzReader.read(fileFromPath: voicesFile), !styles.isEmpty else {
            throw SpeechSynthesisError.message("No voices could be loaded from \(voicesFile.path)")
        }
        if let gpuCacheLimit { GPU.set(cacheLimit: gpuCacheLimit) }
        if let gpuMemoryLimit { GPU.set(memoryLimit: gpuMemoryLimit) }
        return KokoroSynthesizer(engine: KokoroTTS(modelPath: model), styles: styles)
    }

    public static func synchronizeGPU() {
        Stream.gpu.synchronize()
    }

    public static func clearGPUCache() {
        GPU.clearCache()
    }

    public func generate(text: String, voice: String, format: AVAudioFormat) throws
        -> (buffer: AVAudioPCMBuffer, words: [SpokenWord]) {
        guard let style = styles[voice + ".npy"] else {
            throw SpeechSynthesisError.message("Unknown voice '\(voice)'.")
        }
        let language: Language = voice.hasPrefix("a") ? .enUS : .enGB
        let (audio, tokens) = try engine.generateAudio(voice: style, language: language, text: text, speed: 1.0)
        guard !audio.isEmpty, audio.allSatisfy({ $0.isFinite }),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.count)),
              let destination = buffer.floatChannelData?[0] else {
            throw SpeechSynthesisError.message("Synthesis returned empty or invalid audio.")
        }
        buffer.frameLength = AVAudioFrameCount(audio.count)
        audio.withUnsafeBufferPointer { samples in
            destination.update(from: samples.baseAddress!, count: samples.count)
        }
        let words = (tokens ?? []).map { SpokenWord(text: $0.text, start: $0.start_ts, end: $0.end_ts) }
        return (buffer, words)
    }
}
