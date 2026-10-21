#if os(iOS)
import AVFoundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import Pagehum

/// Opt-in integration test: public websites, real speech synthesis and real audio playback.
/// Run the Pagehum-PlaybackDiagnostics scheme on a simulator or physical device.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PAGEHUM_LIVE_BLOG_TESTS"] == "1"))
struct LiveBlogPlaybackTests {
    @Test(.timeLimit(.minutes(10)))
    func listensToBlogsAndExercisesPlaybackTransitions() async throws {
        let defaults = UserDefaults.standard
        let savedSpeed = defaults.object(forKey: "playbackSpeed")
        let savedVoice = defaults.object(forKey: "selectedVoice")
        defer {
            defaults.set(savedSpeed, forKey: "playbackSpeed")
            defaults.set(savedVoice, forKey: "selectedVoice")
        }
        let schema = Schema([PlaylistItem.self, ListeningRecord.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = ReaderModel(loadModelOnInit: false)
        model.modelContext = container.mainContext
        defer { model.stop() }
        await model.loadSpeechEngine()
        try #require(model.isModelLoaded)
        try await waitFor("foreground app") { UIApplication.shared.applicationState == .active }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let readerWindow = UIWindow(windowScene: scene)
        readerWindow.rootViewController = UIHostingController(rootView: NavigationStack {
            PhoneReaderView(viewModel: model)
        })
        readerWindow.makeKeyAndVisible()
        defer {
            readerWindow.isHidden = true
            previousWindow?.makeKey()
        }
        print("PLAYBACK_DIAGNOSTIC engine=\(String(describing: type(of: model.speechEngine!)))")

        let urls = [
            "https://unsung.aresluna.org/good-type-against-all-odds/",
            "https://martinfowler.com/bliki/TwoHardThings.html"
        ]
        var articles: [PlaylistItem] = []
        for url in urls {
            await model.loadURL(url)
            try #require(model.errorMessage == nil, "Article load failed: \(model.errorMessage ?? "")")
            try #require(model.sentences.count > 3)
            print("PLAYBACK_DIAGNOSTIC loaded=\(url) sentences=\(model.sentences.count)")
            let id = try #require(model.currentPlaylistItemID)
            let item = try #require(try container.mainContext.fetch(FetchDescriptor<PlaylistItem>()).first { $0.persistentModelID == id })
            articles.append(item)
            model.speed = 2
            model.play()
            try await waitFor("initial audible playback") { model.isPlaying }
            try await waitFor("spoken word highlighting") { !model.currentWordText.isEmpty }
            let startingIndex = model.currentSentenceIndex
            try await waitFor("three real sentence transitions", seconds: 90) {
                model.currentSentenceIndex >= startingIndex + 3
            }
            print("PLAYBACK_DIAGNOSTIC played=\(url) sentence=\(model.currentSentenceIndex) word=\(model.currentWordText)")
            try #require(model.playbackFailureCount == 0)

            model.pause()
            #expect(model.isPaused && !model.isPlaying)
            model.speed = 1.25
            model.play()
            try await waitFor("resume") { model.isPlaying }
            model.skipForward()
            try await waitFor("forward seek") { model.isPlaying }
            model.skipBackward()
            try await waitFor("backward seek") { model.isPlaying }
            let middleIndex = model.sentences.count / 2
            model.seekToSentence(middleIndex)
            try await waitFor("mid-article playback", seconds: 90) {
                model.isPlaying && model.currentSentenceIndex >= middleIndex + 2
            }
            model.restartFromBeginning()
            try await waitFor("restart") { model.isPlaying && model.currentSentenceIndex == 0 }
            // Repeated seeks exercise late player completions from the previous session.
            for index in [2, 0, 3, 1, 0] { model.seekToSentence(index) }
            try await waitFor("rapid seeks") { model.isPlaying }
            model.speed = 3
            model.restartFromBeginning()
            try await waitFor("full article playback") { model.isPlaying }
            try await waitFor("full article completion", seconds: 240) { model.progress == 1 && !model.isPlaying }
            try #require(model.playbackFailureCount == 0)
            print("PLAYBACK_DIAGNOSTIC fully played=\(url)")
        }

        model.listeningQueue.enqueue(articles)
        try await waitFor("queue first article") { model.isPlaying && model.currentPlaylistItemID == articles[0].persistentModelID }
        model.seekToSentence(model.sentences.count - 1)
        try await waitFor("automatic queue advance", seconds: 90) {
            model.isPlaying && model.currentPlaylistItemID == articles[1].persistentModelID
        }
        #expect(model.listeningQueue.failure == nil)
        model.listeningQueue.skip()
        #expect(!model.listeningQueue.isActive)
        print("PLAYBACK_DIAGNOSTIC queue advance and skip passed")
    }

    private func waitFor(_ stage: String, seconds: TimeInterval = 45, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        try #require(condition(), "Timed out waiting for \(stage)")
    }
}
#endif
