import AVFoundation
import Testing
@testable import Pagehum

@MainActor
struct SystemSpeechEngineTests {
    @Test
    func synthesizesPipelineFormatAudioWithOrderedWordTimings() async throws {
        let engine = SystemSpeechEngine()
        let voice = try #require(engine.voices.first)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: ReaderModel.sampleRate, channels: 1))
        let audio = try #require(await engine.synthesize("Hello there, quiet reader.", voice: voice, format: format))
        #expect(audio.buffer.format == format)
        let duration = Double(audio.buffer.frameLength) / format.sampleRate
        #expect(duration > 0.3)
        let words = try #require(audio.tokens)
        #expect(words.map(\.text) == ["Hello", "there", "quiet", "reader"])
        let starts = words.compactMap(\.start)
        #expect(starts == starts.sorted())
        #expect(try #require(starts.last) < duration)
        #expect(try #require(words.last?.end) <= duration + 0.001)
        #expect(SystemSpeechEngine.displayName(for: voice) != nil)
        #expect(SystemSpeechEngine.displayName(for: "af_heart") == nil)
    }

    @Test
    func estimatesWordTimingsInProportionToWordLength() throws {
        let timings = try #require(SystemSpeechEngine.estimatedTimings(for: "Hi, wonderful!", duration: 1.3))
        #expect(timings.map(\.text) == ["Hi", "wonderful"])
        #expect(timings[0].start == 0)
        #expect(abs((timings[0].end ?? 0) - 0.3) < 0.0001)
        #expect(abs((timings[1].end ?? 0) - 1.3) < 0.0001)
        #expect(SystemSpeechEngine.estimatedTimings(for: "...", duration: 1) == nil)
    }
}
