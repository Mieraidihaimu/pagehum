// Modified for Pagehum: unified application and command-line naming.
import AVFoundation
import Foundation

/// One encoder for the entire narration. The final pathname appears only on success.
final class AudioExporter {
    private let output: URL
    private let temporary: URL
    private let overwrite: Bool
    private var file: AVAudioFile?
    private(set) var frameCount: Int64 = 0

    init(output: URL, bitRate: Int, overwrite: Bool) throws {
        self.output = output
        self.overwrite = overwrite
        let ext = output.pathExtension.lowercased()
        guard ["wav", "m4a"].contains(ext) else {
            throw SpeechSynthesisError.message("Output must end in .m4a or .wav.")
        }
        if !overwrite && FileManager.default.fileExists(atPath: output.path) {
            throw SpeechSynthesisError.message("Output exists: \(output.path). Use --force to replace it.")
        }
        temporary = output.deletingLastPathComponent()
            .appendingPathComponent(".pagehum-\(UUID().uuidString).\(ext)")
        var settings: [String: Any] = [
            AVSampleRateKey: SpeechSynthesis.sampleRate,
            AVNumberOfChannelsKey: 1
        ]
        if ext == "m4a" {
            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            settings[AVEncoderBitRateKey] = bitRate
        } else {
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = false
        }
        do {
            file = try AVAudioFile(forWriting: temporary, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) throws {
        guard let file else { throw SpeechSynthesisError.message("Audio output is closed.") }
        try file.write(from: buffer)
        frameCount += Int64(buffer.frameLength)
    }

    func finish() throws {
        file = nil // Finalize the container before committing it.
        guard frameCount > 0 else { throw SpeechSynthesisError.message("No audio was generated.") }
        if overwrite && FileManager.default.fileExists(atPath: output.path) {
            _ = try FileManager.default.replaceItemAt(output, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: output)
        }
    }

    deinit {
        file = nil
        try? FileManager.default.removeItem(at: temporary)
    }
}
