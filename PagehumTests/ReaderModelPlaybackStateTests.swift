// Modified for Pagehum: unified application and command-line naming.
import AVFoundation
import SwiftData
import Testing
@testable import Pagehum

@MainActor
struct ReaderModelPlaybackStateTests {
    @Test(arguments: ["pagehum", "speechly"])
    func acceptsCurrentAndLegacySharedLinks(scheme: String) {
        let model = makeModel(player: ControlledAudioBufferPlayer()) { _, format in
            makeAudio(format: format)
        }
        let target = "https://example.com/article?topic=swift&part=2"
        var components = URLComponents()
        components.scheme = scheme
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "url", value: target)]
        model.handleOpenURL(components.url!)
        #expect(model.pendingSharedURL == target)
    }

    @Test
    func transitionsFromPreparingThroughAudiblePausedAndFinished() async throws {
        let player = ControlledAudioBufferPlayer()
        let model = makeModel(player: player) { _, format in
            makeAudio(format: format)
        }
        model.prepareTextPublic("A uniquely generated sentence.")

        model.play()
        #expect(model.isPreparing)
        #expect(!model.isPlaying)

        try await waitUntil { model.isPlaying }
        #expect(!model.isPreparing)
        #expect(!model.isPaused)

        model.pause()
        #expect(!model.isPlaying)
        #expect(model.isPaused)

        model.play()
        #expect(model.isPlaying)
        #expect(!model.isPaused)

        player.completeNext()
        #expect(!model.isPreparing)
        #expect(!model.isPlaying)
        #expect(!model.isPaused)
        #expect(model.progress == 1)
    }

    @Test
    func stoppingWhilePreparingCancelsPlayback() {
        let player = ControlledAudioBufferPlayer()
        let model = makeModel(player: player) { _, format in
            makeAudio(format: format)
        }
        model.prepareTextPublic("A sentence stopped before generation runs.")

        model.play()
        #expect(model.isPreparing)

        model.togglePlayback()

        #expect(!model.isPreparing)
        #expect(!model.isPlaying)
        #expect(!model.isPaused)
        #expect(model.progress == 0)
        #expect(player.scheduledCount == 0)
    }

    @Test
    func seekingWhilePreparingStartsPlaybackAtTheNewPosition() async throws {
        let player = ControlledAudioBufferPlayer()
        let model = makeModel(player: player) { _, format in
            makeAudio(format: format)
        }
        defer { model.stop() }
        model.prepareTextPublic("The first sentence is skipped. The second sentence should play.")
        #expect(model.sentences.count == 2)

        model.play()
        #expect(model.isPreparing)
        model.seekToSentence(1)

        try await waitUntil { model.isPlaying }
        #expect(!model.isPreparing)
        #expect(model.currentSentenceIndex == 1)
        #expect(player.scheduledCount > 0)
    }

    @Test
    func seekingWhilePausedWaitsForAnExplicitPlay() async throws {
        let player = ControlledAudioBufferPlayer()
        let model = makeModel(player: player) { _, format in
            makeAudio(format: format)
        }
        defer { model.stop() }
        model.prepareTextPublic("The first sentence will pause. The second sentence waits for play.")
        model.play()
        try await waitUntil { model.isPlaying }
        model.pause()

        model.seekToSentence(1)
        #expect(!model.isPlaying)
        #expect(!model.isPreparing)
        #expect(player.scheduledCount == 0)
        #expect(model.currentSentenceIndex == 1)

        model.play()
        try await waitUntil { model.isPlaying }
        #expect(model.currentSentenceIndex == 1)
    }

    @Test
    func restartingFromBeginningReplaysTheFirstSentence() async throws {
        let player = ControlledAudioBufferPlayer()
        var generatedTexts: [String] = []
        let model = makeModel(player: player) { text, format in
            generatedTexts.append(text)
            return makeAudio(format: format)
        }
        model.prepareTextPublic(
            "A first uniquely generated sentence. A second uniquely generated sentence.",
            resumeAt: 1
        )

        model.play()
        try await waitUntil { model.isPlaying }
        #expect(model.currentSentenceIndex == 1)

        model.restartFromBeginning()
        #expect(model.currentSentenceIndex == 0)
        #expect(model.isPreparing)

        try await waitUntil { model.isPlaying }
        #expect(model.currentSentenceIndex == 0)
        #expect(generatedTexts.contains(model.sentences[0]))
    }

    @Test
    func restartingWhilePreparingSerializesSentenceGeneration() async throws {
        let player = ControlledAudioBufferPlayer()
        let generator = ControlledAudioGenerator()
        let model = makeModel(player: player) { text, format in
            await generator.generate(text, format: format)
        }
        model.prepareTextPublic("A sentence with deliberately suspended generation.")

        model.play()
        try await waitUntil { generator.pendingCount == 1 }

        model.restartFromBeginning()
        try await Task.sleep(for: .milliseconds(50))
        #expect(generator.maximumActiveCount == 1)

        let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
        generator.completeNext(with: makeAudio(format: format))
        try await waitUntil { generator.pendingCount == 1 }
        #expect(generator.maximumActiveCount == 1)

        generator.completeNext(with: makeAudio(format: format))
        try await waitUntil { model.isPlaying }
    }

    @Test
    func restartingCompletedItemImmediatelyPersistsInProgressState() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PlaylistItem.self, configurations: configuration)
        let item = PlaylistItem(
            title: "Completed item",
            sourceType: "text",
            fullText: "A completed item being read again.",
            status: PlaylistItem.Status.completed.rawValue
        )
        item.progressPercent = 1
        container.mainContext.insert(item)

        let player = ControlledAudioBufferPlayer()
        let model = makeModel(player: player) { _, format in
            makeAudio(format: format)
        }
        model.modelContext = container.mainContext
        model.currentPlaylistItemID = item.persistentModelID
        model.prepareTextPublic(item.fullText)

        model.restartFromBeginning()

        #expect(item.progressPercent == 0)
        #expect(item.status == PlaylistItem.Status.inProgress.rawValue)
        #expect(model.isPreparing)
        model.stop()
    }

    @Test
    func allGenerationFailuresRemainIncompleteAndReportEverySentence() async throws {
        let player = ControlledAudioBufferPlayer()
        let model = makeModel(player: player) { _, _ in nil }
        model.prepareTextPublic("Failure one. Failure two.")
        let sentenceCount = model.sentences.count

        model.play()
        #expect(model.isPreparing)

        try await waitUntil { !model.isPreparing }

        #expect(!model.isPlaying)
        #expect(!model.isPaused)
        #expect(model.progress < 1)
        #expect(model.playbackFailureCount == sentenceCount)
        #expect(player.scheduledCount == 0)
    }

    @Test
    func urlLoadingTimeoutClearsLoadingState() async throws {
        let model = ReaderModel(
            loadModelOnInit: false,
            contentExtractor: SlowContentExtractor(),
            contentLoadTimeout: .milliseconds(25)
        )

        await model.loadURL("https://example.com/article")

        #expect(!model.isLoading)
        #expect(model.content == nil)
        #expect(model.errorMessage != nil)
    }

    private func makeModel(
        player: ControlledAudioBufferPlayer,
        generator: @escaping (String, AVAudioFormat) async -> SentenceAudio?
    ) -> ReaderModel {
        let model = ReaderModel(
            loadModelOnInit: false,
            schedulerPlayer: player,
            audioGenerator: generator
        )
        model.isModelLoaded = true
        return model
    }

    private func makeAudio(format: AVAudioFormat) -> SentenceAudio {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        buffer.frameLength = 1
        return SentenceAudio(buffer: buffer, tokens: nil)
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}

@MainActor
private final class ControlledAudioBufferPlayer: AudioBufferPlayer {
    private var completions: [() -> Void] = []
    private(set) var isPlaying = false

    var scheduledCount: Int { completions.count }

    func schedule(_ buffer: AVAudioPCMBuffer, onComplete: @escaping () -> Void) {
        completions.append(onComplete)
    }

    func play() {
        isPlaying = true
    }

    func pause() {
        isPlaying = false
    }

    func stop() {
        isPlaying = false
        completions = []
    }

    func completeNext() {
        completions.removeFirst()()
    }
}

@MainActor
private final class ControlledAudioGenerator {
    private var continuations: [CheckedContinuation<SentenceAudio?, Never>] = []
    private(set) var activeCount = 0
    private(set) var maximumActiveCount = 0

    var pendingCount: Int { continuations.count }

    func generate(_ text: String, format: AVAudioFormat) async -> SentenceAudio? {
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func completeNext(with audio: SentenceAudio) {
        activeCount -= 1
        continuations.removeFirst().resume(returning: audio)
    }
}

@MainActor
private final class SlowContentExtractor: ContentExtracting {
    func extract(from source: ContentSource) async throws -> ReadingContent {
        try await Task.sleep(for: .seconds(30))
        return ReadingContent(title: "Late", body: "Late body.", source: source)
    }
}
