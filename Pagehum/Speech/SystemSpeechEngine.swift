import AVFoundation

/// Apple's built-in voices, used when Kokoro can't run (iOS Simulator, missing model, no GPU).
/// The synthesizer reports no word markers for these voices, so word timings are estimated.
final class SystemSpeechEngine: SpeechEngine {
    private static let prefix = "system:"
    let voices: [String]
    let defaultVoice: String?
    private let synthesizer = AVSpeechSynthesizer()

    init() {
        voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") && $0.voiceTraits.isDisjoint(with: [.isNoveltyVoice, .isPersonalVoice]) }
            .sorted { ($0.language == "en-US" ? 0 : 1, $0.language, $0.name) < ($1.language == "en-US" ? 0 : 1, $1.language, $1.name) }
            .map { Self.prefix + $0.identifier }
        defaultVoice = AVSpeechSynthesisVoice(language: "en-US").map { Self.prefix + $0.identifier }
    }

    static func displayName(for voice: String) -> String? {
        guard let systemVoice = systemVoice(for: voice) else { return nil }
        let language = Locale.current.localizedString(forIdentifier: systemVoice.language) ?? systemVoice.language
        return "\(systemVoice.name) · \(language)"
    }

    func synthesize(_ text: String, voice: String, format: AVAudioFormat) async -> SentenceAudio? {
        guard let systemVoice = Self.systemVoice(for: voice),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = systemVoice
        let collected = SpeechChunks()
        let synthesizer = self.synthesizer
        let chunks = await withCheckedContinuation { continuation in
            synthesizer.write(utterance) { @Sendable buffer in
                if let finished = collected.append(buffer) { continuation.resume(returning: finished) }
            }
            Task {
                try? await Task.sleep(for: .seconds(30))
                guard let partial = collected.finish() else { return }
                synthesizer.stopSpeaking(at: .immediate)
                continuation.resume(returning: partial)
            }
        }
        guard let audio = Self.convert(chunks, to: format) else { return nil }
        let duration = Double(audio.frameLength) / format.sampleRate
        return SentenceAudio(buffer: audio, tokens: Self.estimatedTimings(for: text, duration: duration))
    }

    /// Spreads `duration` across words in proportion to their length plus one for the gap.
    static func estimatedTimings(for text: String, duration: Double) -> [WordTiming]? {
        let words = text.split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" }.map(String.init)
        guard !words.isEmpty, duration > 0 else { return nil }
        let weights = words.map { Double($0.count + 1) }
        let total = weights.reduce(0, +)
        var start = 0.0
        return zip(words, weights).map { word, weight in
            let end = start + duration * weight / total
            defer { start = end }
            return WordTiming(text: word, start: start, end: end)
        }
    }

    private static func systemVoice(for voice: String) -> AVSpeechSynthesisVoice? {
        guard voice.hasPrefix(prefix) else { return nil }
        return AVSpeechSynthesisVoice(identifier: String(voice.dropFirst(prefix.count)))
    }

    private static func convert(_ chunks: [AVAudioPCMBuffer], to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let source = chunks.first?.format, let converter = AVAudioConverter(from: source, to: format) else { return nil }
        let inputFrames = chunks.reduce(0.0) { $0 + Double($1.frameLength) }
        let capacity = AVAudioFrameCount((inputFrames * format.sampleRate / source.sampleRate).rounded(.up)) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var pending = chunks[...]
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            guard let next = pending.popFirst() else {
                inputStatus.pointee = .endOfStream
                return nil
            }
            inputStatus.pointee = .haveData
            return next
        }
        guard status != .error, error == nil, output.frameLength > 0 else { return nil }
        return output
    }
}

/// Collects synthesizer output from whichever thread delivers it; an empty buffer marks the end.
nonisolated private final class SpeechChunks: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [AVAudioPCMBuffer] = []
    private var finished = false

    /// Returns every buffer once, when the end-of-utterance buffer arrives.
    func append(_ buffer: AVAudioBuffer) -> [AVAudioPCMBuffer]? {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return nil }
        if let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 {
            buffers.append(pcm)
            return nil
        }
        finished = true
        return buffers
    }

    func finish() -> [AVAudioPCMBuffer]? {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return nil }
        finished = true
        return buffers
    }
}
