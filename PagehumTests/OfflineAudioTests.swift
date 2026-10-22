import AVFoundation
import SwiftData
import Testing
@testable import Pagehum

@MainActor
@Suite(.serialized)
struct OfflineAudioTests {
    @Test
    func savesBulkArticlesAndPlaysWholeQueueWithoutAnEngineInBackground() async throws {
        let fixture = try await OfflineFixture()
        defer { fixture.cleanup() }
        let articles = try ["First", "Second", "Third"].map { try fixture.add($0) }
        fixture.model.saveAudioOffline(articles)
        try await fixture.wait {
            articles.allSatisfy { fixture.model.offlineAudio.progress[fixture.model.offlineAudioID(for: $0)]?.state == .ready }
        }
        #expect(fixture.store.allRecords().allSatisfy { $0.isReady })
        let savedCount = fixture.engine.calls.count

        // Reopen durable manifests, disable inference, and start a cold player in the background.
        let restored = OfflineAudioStore(directory: fixture.directory)
        let player = OfflineTestPlayer()
        var inferenceCalls = 0
        let model = ReaderModel(loadModelOnInit: false, schedulerPlayer: player, audioGenerator: { _, _ in
            inferenceCalls += 1
            return nil
        }, fallbackSpeechEngine: nil, offlineStore: restored, applicationIsActive: { false })
        model.modelContext = fixture.container.mainContext
        model.speed = 2.25
        defer { model.listeningQueue.end(); model.stop() }
        model.listeningQueue.enqueue(articles)
        try #require(model.isPlaying)
        #expect(!model.isModelLoaded)
        #expect(model.isCurrentAudioSaved)
        #expect(model.speed == 2.25)
        for article in articles {
            try await fixture.wait { model.currentPlaylistItemID == article.persistentModelID && model.isPlaying }
            for expectedIndex in model.sentences.indices {
                #expect(model.currentSentenceIndex == expectedIndex)
                try #require(player.count > 0)
                player.completeNext()
            }
            #expect(article.progressPercent == 1)
        }
        try await fixture.wait { !model.listeningQueue.isActive }
        #expect(inferenceCalls == 0)
        #expect(fixture.engine.calls.count == savedCount)
        #expect(model.listeningQueue.failure == nil)
        #expect(!model.isWaitingForOfflineAudio)
    }

    @Test
    func partialSavesResumeAfterRelaunchWithoutRepeatingSavedSentences() async throws {
        let fixture = try await OfflineFixture()
        defer { fixture.cleanup() }
        let item = try fixture.add("Resumable")
        let request = fixture.model.offlineRequest(for: item)
        _ = try fixture.store.register(request)
        _ = try fixture.store.save(OfflineTestEngine.audio(), id: request.id, index: 0)
        fixture.store.pause(request.id)
        let reopened = OfflineAudioStore(directory: fixture.directory)
        var generated: [String] = []
        let manager = OfflineAudioManager(store: reopened, canPrepare: { true }, generate: { text, _ in
            generated.append(text)
            return OfflineTestEngine.audio()
        })
        #expect(manager.progress[request.id]?.state == .paused)
        manager.enqueue([request, request])
        try await fixture.wait { manager.progress[request.id]?.state == .ready }
        #expect(generated == Array(request.sentences.dropFirst()))
        #expect(reopened.record(request.id)?.completed.count == request.sentences.count)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).count == 1)
    }

    @Test
    func failedSentenceDoesNotMarkArticleReadyAndRetryKeepsCheckpoint() async throws {
        let fixture = try await OfflineFixture()
        defer { fixture.cleanup() }
        let request = fixture.model.offlineRequest(for: try fixture.add("Retry"))
        var shouldFail = true
        var generated: [String] = []
        let manager = OfflineAudioManager(store: fixture.store, canPrepare: { true }, generate: { text, _ in
            generated.append(text)
            if shouldFail && text == request.sentences[1] { return nil }
            return OfflineTestEngine.audio()
        })
        manager.enqueue([request])
        try await fixture.wait { manager.progress[request.id]?.state == .failed }
        #expect(fixture.store.record(request.id)?.completed.count == 1)
        #expect(fixture.store.readyRequest(textID: request.textID, preferredVoice: request.voice) == nil)
        shouldFail = false
        generated = []
        manager.enqueue([request])
        try await fixture.wait { manager.progress[request.id]?.state == .ready }
        #expect(generated == Array(request.sentences.dropFirst()))
    }

    @Test
    func preparationWaitsForForegroundAndPausePersistsAcrossRelaunch() async throws {
        let fixture = try await OfflineFixture()
        defer { fixture.cleanup() }
        let request = fixture.model.offlineRequest(for: try fixture.add("Foreground"))
        var active = false
        var calls = 0
        let manager = OfflineAudioManager(store: fixture.store, canPrepare: { active }, generate: { _, _ in
            calls += 1
            return OfflineTestEngine.audio()
        })
        manager.enqueue([request])
        manager.suspend()
        try await Task.sleep(for: .milliseconds(30))
        #expect(calls == 0)
        #expect(manager.progress[request.id]?.state == .waitingForForeground)
        manager.pause(request.id)
        active = true
        manager.resume()
        #expect(calls == 0)
        #expect(OfflineAudioStore(directory: fixture.directory).record(request.id)?.userPaused == true)
        manager.enqueue([request])
        try await fixture.wait { manager.progress[request.id]?.state == .ready }
        #expect(calls == request.sentences.count)
    }

    @Test
    func missingFilesInvalidateReadinessAndRemovalDoesNotTouchOtherArticles() async throws {
        let fixture = try await OfflineFixture()
        defer { fixture.cleanup() }
        let items = try [fixture.add("One"), fixture.add("Two")]
        fixture.model.saveAudioOffline(items)
        try await fixture.wait { fixture.store.allRecords().count == 2 && fixture.store.allRecords().allSatisfy { $0.isReady } }
        let first = fixture.model.offlineRequest(for: items[0])
        let second = fixture.model.offlineRequest(for: items[1])
        let audioFolder = fixture.directory.appendingPathComponent(first.id).appendingPathComponent("Audio")
        let clip = try #require(try FileManager.default.contentsOfDirectory(at: audioFolder, includingPropertiesForKeys: nil).first { $0.pathExtension == "m4a" })
        try FileManager.default.removeItem(at: clip)
        let reopened = OfflineAudioStore(directory: fixture.directory)
        #expect(reopened.record(first.id)?.isReady == false)
        #expect(reopened.record(second.id)?.isReady == true)
        try reopened.remove(first.id)
        #expect(reopened.record(first.id) == nil)
        #expect(reopened.load(id: second.id, index: 0) != nil)
    }

    @Test
    func unpreparedBackgroundArticlePausesAtItsPositionInsteadOfHanging() async throws {
        let fixture = try await OfflineFixture()
        defer { fixture.cleanup() }
        let model = ReaderModel(loadModelOnInit: false, schedulerPlayer: OfflineTestPlayer(),
                                fallbackSpeechEngine: nil, offlineStore: fixture.store, applicationIsActive: { false })
        model.isModelLoaded = true
        model.prepareTextPublic("\(UUID().uuidString) has no saved audio. Another sentence.", resumeAt: 1)
        model.play()
        #expect(model.isWaitingForOfflineAudio)
        #expect(model.isPaused)
        #expect(!model.isPlaying && !model.isPreparing)
        #expect(model.currentSentenceIndex == 1)
        model.stop()
    }
}

@MainActor
private final class OfflineFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("offline-tests-\(UUID().uuidString)")
    let container: ModelContainer
    let engine = OfflineTestEngine()
    let store: OfflineAudioStore
    let model: ReaderModel
    private let savedSpeed = UserDefaults.standard.object(forKey: "playbackSpeed")
    private let savedVoice = UserDefaults.standard.object(forKey: "selectedVoice")

    init() async throws {
        container = try ModelContainer(for: PlaylistItem.self, ListeningRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        store = OfflineAudioStore(directory: directory)
        let engine = engine
        model = ReaderModel(loadModelOnInit: false, speechEngineLoader: { engine }, fallbackSpeechEngine: nil,
                            offlineStore: store, applicationIsActive: { true })
        model.modelContext = container.mainContext
        await model.loadSpeechEngine()
    }

    func add(_ title: String) throws -> PlaylistItem {
        let item = PlaylistItem(title: title, sourceType: "text", fullText: "\(UUID().uuidString) first sentence. A second sentence. A final sentence.")
        container.mainContext.insert(item)
        try container.mainContext.save()
        return item
    }

    func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }

    func cleanup() {
        model.stop()
        for record in store.allRecords() { model.offlineAudio.pause(record.request.id) }
        try? FileManager.default.removeItem(at: directory)
        UserDefaults.standard.set(savedSpeed, forKey: "playbackSpeed")
        UserDefaults.standard.set(savedVoice, forKey: "selectedVoice")
    }
}

@MainActor
private final class OfflineTestEngine: SpeechEngine {
    let voices = ["offline-test-\(UUID().uuidString)"]
    private(set) var calls: [String] = []
    func synthesize(_ text: String, voice: String, format: AVAudioFormat) async -> SentenceAudio? {
        calls.append(text)
        return Self.audio()
    }
    static func audio() -> SentenceAudio {
        let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800)!
        buffer.frameLength = 4_800
        for index in 0..<4_800 { buffer.floatChannelData![0][index] = Float(sin(Double(index) * 0.08)) * 0.05 }
        return SentenceAudio(buffer: buffer, tokens: [WordTiming(text: "test", start: 0, end: 0.2)])
    }
}

@MainActor
private final class OfflineTestPlayer: AudioBufferPlayer {
    private(set) var isPlaying = false
    private var completions: [() -> Void] = []
    var count: Int { completions.count }
    func schedule(_ buffer: AVAudioPCMBuffer, onComplete: @escaping () -> Void) { completions.append(onComplete) }
    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func stop() { isPlaying = false; completions = [] }
    func completeNext() { if !completions.isEmpty { completions.removeFirst()() } }
}
