import AVFoundation
import SpeechCore
import Testing
@testable import Pagehum

@MainActor
struct SpeechEngineTests {
    @Test
    func loadingAnEngineListsItsVoicesAndKeepsTheStoredVoice() async {
        let saved = UserDefaults.standard.string(forKey: "selectedVoice")
        defer { UserDefaults.standard.set(saved, forKey: "selectedVoice") }
        UserDefaults.standard.set("bm_george", forKey: "selectedVoice")
        let model = ReaderModel(loadModelOnInit: false, speechEngineLoader: { FakeSpeechEngine(voices: ["af_heart", "bm_george"]) })
        await model.loadSpeechEngine()
        #expect(model.isModelLoaded)
        #expect(model.voiceNames == ["af_heart", "bm_george"])
        #expect(model.selectedVoice == "bm_george")
    }

    @Test
    func unknownStoredVoiceFallsBackToAnAmericanVoice() async {
        let saved = UserDefaults.standard.string(forKey: "selectedVoice")
        defer { UserDefaults.standard.set(saved, forKey: "selectedVoice") }
        UserDefaults.standard.set("missing", forKey: "selectedVoice")
        let model = ReaderModel(loadModelOnInit: false, speechEngineLoader: { FakeSpeechEngine(voices: ["bf_emma", "af_heart"]) })
        await model.loadSpeechEngine()
        #expect(model.selectedVoice == "af_heart")
    }

    @Test
    func engineFailureReportsTheErrorAndStaysUnloadedWithoutAFallback() async {
        let model = ReaderModel(loadModelOnInit: false, speechEngineLoader: { throw SpeechSynthesisError.message("No GPU") },
                                fallbackSpeechEngine: nil)
        await model.loadSpeechEngine()
        #expect(!model.isModelLoaded)
        #expect(model.errorMessage == "No GPU")
    }

    @Test
    func engineFailureFallsBackToSystemVoicesAndExplainsWhy() async {
        let saved = UserDefaults.standard.string(forKey: "selectedVoice")
        defer { UserDefaults.standard.set(saved, forKey: "selectedVoice") }
        let model = ReaderModel(loadModelOnInit: false, speechEngineLoader: { throw SpeechSynthesisError.message("No GPU") },
                                fallbackSpeechEngine: { FakeSpeechEngine(voices: ["system:samantha"]) })
        await model.loadSpeechEngine()
        #expect(model.isModelLoaded)
        #expect(model.voiceNames == ["system:samantha"])
        #expect(model.selectedVoice == "system:samantha")
        #expect(model.errorMessage == nil)
        #expect(model.speechEngineNotice?.contains("No GPU") == true)
    }
}

final class FakeSpeechEngine: SpeechEngine {
    let voices: [String]
    init(voices: [String]) { self.voices = voices }
    func synthesize(_ text: String, voice: String, format: AVAudioFormat) async -> SentenceAudio? { nil }
}
