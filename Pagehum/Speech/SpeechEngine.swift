import AVFoundation

/// A text-to-speech backend. `ReaderModel` depends only on this, never on Kokoro or MLX.
/// Implementations return audio in the `format` they are given, or `nil` to skip the sentence.
protocol SpeechEngine: AnyObject {
    /// Voice identifiers for the voice picker, in display order, e.g. "af_heart".
    var voices: [String] { get }
    /// Preferred voice when the user hasn't chosen one this engine offers.
    var defaultVoice: String? { get }
    func synthesize(_ text: String, voice: String, format: AVAudioFormat) async -> SentenceAudio?
}

extension SpeechEngine {
    var defaultVoice: String? { nil }
}
