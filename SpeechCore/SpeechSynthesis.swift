// Modified for Pagehum: unified application and command-line naming.
import AVFoundation
import Foundation
import KokoroSwift
import MLX
import MLXUtilsLibrary
import Metal

nonisolated enum SpeechSynthesisError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

/// Synchronous boundary. Call only on a dedicated dispatch queue, never the
/// cooperative executor: MLX performs blocking dispatch internally.
nonisolated enum SpeechSynthesis {
    static let sampleRate = Double(KokoroTTS.Constants.samplingRate)

    static func load(directory: URL) throws -> (KokoroTTS, [String: MLXArray]) {
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
        guard let voices = NpyzReader.read(fileFromPath: voicesFile), !voices.isEmpty else {
            throw SpeechSynthesisError.message("No voices could be loaded from \(voicesFile.path)")
        }
        return (KokoroTTS(modelPath: model), voices)
    }

    static func generate(engine: KokoroTTS, voice: MLXArray, language: Language,
                         text: String, format: AVAudioFormat) throws
        -> (buffer: AVAudioPCMBuffer, timings: [WordTiming]) {
        let (audio, tokens) = try engine.generateAudio(voice: voice, language: language, text: text, speed: 1.0)
        guard !audio.isEmpty, audio.allSatisfy({ $0.isFinite }),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.count)),
              let destination = buffer.floatChannelData?[0] else {
            throw SpeechSynthesisError.message("Synthesis returned empty or invalid audio.")
        }
        buffer.frameLength = AVAudioFrameCount(audio.count)
        audio.withUnsafeBufferPointer { samples in
            destination.update(from: samples.baseAddress!, count: samples.count)
        }
        let timings = (tokens ?? []).map { WordTiming(text: $0.text, start: $0.start_ts, end: $0.end_ts) }
        return (buffer, timings)
    }
}
