// Modified for Pagehum: unified application and command-line naming.
import AVFoundation
import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif
import Combine
import NaturalLanguage
import SpeechCore
#if canImport(MediaPlayer)
import MediaPlayer
#endif

private extension Float {
    func clamped(fallback: Float) -> Float {
        self == 0 ? fallback : self
    }
}

private extension Double {
    func clamped(fallback: Double) -> Double {
        self == 0 ? fallback : self
    }
}

nonisolated struct SentenceAudio {
    let buffer: AVAudioPCMBuffer
    let tokens: [WordTiming]?
    /// Leading-silence compensation (seconds) applied to `bufferStartTime` for AAC-decoded cache
    /// hits whose priming couldn't be trimmed. 0 for freshly generated or trimmed audio.
    var leadingSilence: TimeInterval = 0
}

private enum ContentLoadError: LocalizedError {
    case timedOut

    var errorDescription: String? {
        "The page took too long to load. Please try again."
    }
}

nonisolated private final class ContentLoadContinuationBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var isResolved = false

    func set(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func resume(returning value: Value) {
        resolve { $0.resume(returning: value) }
    }

    func resume(throwing error: Error) {
        resolve { $0.resume(throwing: error) }
    }

    private func resolve(_ resume: (CheckedContinuation<Value, Error>) -> Void) {
        lock.lock()
        guard !isResolved, let continuation else {
            lock.unlock()
            return
        }
        isResolved = true
        self.continuation = nil
        lock.unlock()
        resume(continuation)
    }
}

@MainActor
final class ReaderModel: ObservableObject {

    /// Kokoro's native rate; every `SpeechEngine` delivers audio in this mono float format.
    static let sampleRate: Double = 24_000

    private(set) var speechEngine: (any SpeechEngine)?
    private let speechEngineLoader: () async throws -> any SpeechEngine
    private let fallbackSpeechEngine: (@MainActor () -> any SpeechEngine)?
    /// Explains why system voices are in use instead of Kokoro.
    @Published private(set) var speechEngineNotice: String?
    private let modelStore: ModelStore

    enum ModelDownloadState: Equatable {
        case idle, downloading(Double), failed(String)
    }
    @Published private(set) var modelDownload: ModelDownloadState = .idle
    let audioEngine: AVAudioEngine!
    let playerNode: AVAudioPlayerNode!
    let timePitch: AVAudioUnitTimePitch!
    private var fallbackEngineInstance: (any SpeechEngine)?

    #if os(iOS)
    @Published private(set) var isAppInBackground = false
    #else
    private let isAppInBackground = false
    #endif

    @Published var isModelLoaded = false
    @Published var voiceNames: [String] = []
    @Published var isPlaying = false
    @Published var isPaused = false
    @Published var currentSentenceIndex = 0
    @Published var currentWordText = ""
    @Published var currentTokenIndex = -1
    @Published var progress: Double = 0
    @Published var isGenerating = false
    @Published private(set) var isPreparing = false
    @Published private(set) var playbackFailureCount = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var content: ReadingContent?
    @Published var savedConfirmation = false
    @Published private(set) var importProgress: String?
    @Published private(set) var importResult: URLImportResult?
    @Published private(set) var techBlogMessage: String?
    @Published var techBlogSettings = TechBlogSettings.load() {
        didSet { techBlogSettings.save() }
    }
    @Published private(set) var techBlogStories: [TechBlogStory] = []
    @Published private(set) var savedTechBlogKeys: Set<String> = []
    var modelContext: ModelContext?
    @Published var currentPlaylistItemID: PersistentIdentifier?
    lazy var listeningQueue = ListeningQueue(model: self)
    private let offlineStore: OfflineAudioStore
    private let applicationIsActive: () -> Bool
    private var currentTextID = ""
    @Published private(set) var currentOfflineAudioID: String?
    private var activeOfflineAudioID: String?
    @Published private(set) var isWaitingForOfflineAudio = false
    lazy var offlineAudio = OfflineAudioManager(store: offlineStore, canPrepare: { [weak self] in
        guard let self else { return false }
        return self.isModelLoaded && self.canRunSpeechWork
    }, generate: { [weak self] text, voice in
        guard let self else { return nil }
        return await self.generateSentenceAudio(for: text, format: self.audioFormat, voice: voice, allowFallback: false)
    })

    private var canRunSpeechWork: Bool { !isAppInBackground && applicationIsActive() }
    var isCurrentAudioSaved: Bool {
        !currentTextID.isEmpty && offlineStore.readyRequest(textID: currentTextID, preferredVoice: selectedVoice) != nil
    }
    var canPlayCurrentContent: Bool { !sentences.isEmpty && (isModelLoaded || isCurrentAudioSaved) }

    @Published var speed: Float = UserDefaults.standard.float(forKey: "playbackSpeed").clamped(fallback: 1.0) {
        didSet {
            timePitch.rate = speed
            UserDefaults.standard.set(speed, forKey: "playbackSpeed")
            // Recalibrate bufferStartTime so word highlight stays in sync at new speed.
            // We know: elapsed_audio = wallElapsed_old * oldSpeed
            // We want: elapsed_audio = wallElapsed_new * newSpeed
            // So: wallElapsed_new = elapsed_audio / newSpeed
            if isPlaying, let start = bufferStartTime, speed > 0 {
                let elapsedAudio = Date().timeIntervalSince(start) * Double(oldValue)
                bufferStartTime = Date().addingTimeInterval(-elapsedAudio / Double(speed))
            }
            if isPlaying, let start = listeningSessionStart {
                listeningAccumulator += Date().timeIntervalSince(start) * Double(oldValue)
                listeningSessionStart = Date()
            }
            updateNowPlayingInfo()
        }
    }

    @Published var selectedVoice: String = UserDefaults.standard.string(forKey: "selectedVoice") ?? "" {
        didSet {
            UserDefaults.standard.set(selectedVoice, forKey: "selectedVoice")
            refreshOfflineAudioIdentity()
            guard oldValue != selectedVoice, isPlaying else { return }
            // Restart pipeline with new voice — clear cached audio from old voice
            generationTask?.cancel()
            audioCache = [:]; skippedSentences = []
            startPipeline()
        }
    }

    @Published var textSize: Double = UserDefaults.standard.double(forKey: "textSize").clamped(fallback: 17) {
        didSet {
            UserDefaults.standard.set(textSize, forKey: "textSize")
        }
    }

    var sentences: [String] = []
    private var sentenceStartOffsetsUTF16: [Int] = []

    /// Code blocks lifted out of the spoken stream, keyed by their index in `sentences`.
    ///
    /// Where `codeBlocks[i]` exists, `sentences[i]` holds that block's short spoken announcement
    /// ("Swift code block, 12 lines.") instead of prose, and the reader renders a code card rather
    /// than a `SentenceView`. Keeping code in the sentence index space means the scheduler,
    /// pipeline, seek, progress and resume all work unchanged. See `ArticleSegmenter`.
    @Published private(set) var codeBlocks: [Int: CodeBlock] = [:]

    private var fullText = ""
    private let extractor: ContentExtracting
    private let contentLoadTimeout: Duration
    private let audioGenerator: ((String, AVAudioFormat) async -> SentenceAudio?)?

    // Pipeline: cache of pre-generated audio
    private var audioCache: [Int: SentenceAudio] = [:]
    private var skippedSentences: Set<Int> = []
    private var generationTask: Task<Void, Never>?
    private var isSynthesisInFlight = false
    private let lookaheadCount = 100

    // Gapless playback: schedules cached buffers back-to-back on the player node.
    // See docs/IMPROVEMENT_PLAN.md (A2). Set up in init once playerNode exists.
    private var scheduler: GaplessSentenceScheduler!

    // Word tracking
    private var currentTokens: [WordTiming]?
    private var bufferStartTime: Date?
    private var wordTimer: Timer?
    private var pauseElapsed: TimeInterval = 0

    // Listening time tracking
    private var listeningSessionStart: Date?
    private var listeningAccumulator: TimeInterval = 0
    private var listeningSaveTimer: Timer?


    private var sampleRate: Double { Self.sampleRate }
    private var audioFormat: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    }

    private static func makeSilenceBuffer(format: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(format.sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        if let channels = buffer.floatChannelData {
            for c in 0..<Int(format.channelCount) {
                for frame in 0..<Int(frameCount) {
                    // Non-zero LSB comfort dither (~ -90 dBFS) keeps mediaserverd actively rendering
                    channels[c][frame] = frame.isMultiple(of: 2) ? 1.0e-5 : -1.0e-5
                }
            }
        }
        return buffer
    }

    init(
        loadModelOnInit: Bool = ProcessInfo.processInfo.environment["KOKORO_SKIP_MODEL_LOADING"] != "1",
        schedulerPlayer: AudioBufferPlayer? = nil,
        contentExtractor: ContentExtracting? = nil,
        contentLoadTimeout: Duration = .seconds(45),
        audioGenerator: ((String, AVAudioFormat) async -> SentenceAudio?)? = nil,
        speechEngineLoader: (() async throws -> any SpeechEngine)? = nil,
        fallbackSpeechEngine: (@MainActor () -> any SpeechEngine)? = { SystemSpeechEngine() },
        modelStore: ModelStore = .standard,
        offlineStore: OfflineAudioStore = .standard,
        applicationIsActive: @escaping () -> Bool = {
            #if os(iOS)
            UIApplication.shared.applicationState == .active
            #else
            true
            #endif
        }
    ) {
        self.offlineStore = offlineStore
        self.applicationIsActive = applicationIsActive
        self.extractor = contentExtractor ?? TextExtractor()
        self.contentLoadTimeout = contentLoadTimeout
        self.audioGenerator = audioGenerator
        self.fallbackSpeechEngine = fallbackSpeechEngine
        self.modelStore = modelStore
        self.speechEngineLoader = speechEngineLoader ?? {
            #if targetEnvironment(simulator)
            throw SpeechSynthesisError.message("Kokoro can’t run in the iOS Simulator")
            #else
            guard let directory = modelStore.modelDirectory() else {
                throw SpeechSynthesisError.message("the voice model hasn’t been downloaded yet")
            }
            return try await KokoroSpeechEngine.load(directory: directory)
            #endif
        }
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        timePitch = AVAudioUnitTimePitch()
        timePitch.rate = 1.0

        audioEngine.attach(playerNode)
        audioEngine.attach(timePitch)

        let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)!
        audioEngine.connect(playerNode, to: timePitch, format: format)
        audioEngine.connect(timePitch, to: audioEngine.mainMixerNode, format: format)

        if let fallbackSpeechEngine {
            self.fallbackEngineInstance = fallbackSpeechEngine()
        }

        let storedSpeed = UserDefaults.standard.float(forKey: "playbackSpeed")

        // Configure gapless scheduling. `self` is fully initialized below this point for stored
        // properties, so it is safe to reference as the buffer provider and in the callbacks.
        scheduler = GaplessSentenceScheduler(
            player: schedulerPlayer ?? AVAudioPlayerNodeAdapter(playerNode),
            provider: self,
            maxInFlight: 3,
            silenceBridgeBuffer: Self.makeSilenceBuffer(format: format, seconds: 0.5)
        )
        scheduler.onSentenceStarted = { [weak self] index, audio in
            self?.handleSentenceStarted(index: index, audio: audio)
        }
        scheduler.onFinished = { [weak self] in
            self?.handlePlaybackFinished()
        }
        scheduler.onWaitingForAudio = { [weak self] index in
            self?.handleWaitingForAudio(at: index)
        }

        if storedSpeed > 0 { timePitch.rate = storedSpeed; speed = storedSpeed }

        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
        setupRemoteTransportControls()
        setupAudioSessionObservers()
        #endif

        if loadModelOnInit {
            Task { await loadSpeechEngine() }
        }
    }

    func loadSpeechEngine() async {
        let engine: any SpeechEngine
        do {
            engine = try await speechEngineLoader()
            speechEngineNotice = nil
        } catch {
            guard let fallback = fallbackEngineInstance ?? fallbackSpeechEngine?(), !fallback.voices.isEmpty else {
                errorMessage = error.localizedDescription
                return
            }
            if fallbackEngineInstance == nil { fallbackEngineInstance = fallback }
            engine = fallback
            speechEngineNotice = "Natural voices aren’t available (\(error.localizedDescription)). Using system voices."
        }

        speechEngine = engine
        voiceNames = engine.voices

        let storedVoice = UserDefaults.standard.string(forKey: "selectedVoice") ?? ""
        if voiceNames.contains(storedVoice) {
            selectedVoice = storedVoice
        } else if let preferred = engine.defaultVoice, voiceNames.contains(preferred) {
            selectedVoice = preferred
        } else {
            selectedVoice = voiceNames.first(where: { $0.hasPrefix("af") }) ?? voiceNames.first ?? ""
        }
        isModelLoaded = true
        offlineAudio.resume()
    }

    /// True when system voices are in use only because the Kokoro model isn't on this device yet.
    var canDownloadVoiceModel: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        speechEngineNotice != nil && modelStore.modelDirectory() == nil
        #endif
    }

    var voiceModelDownloadSize: Int64 { modelStore.downloadSize }

    /// Downloads and verifies the model, then switches to Kokoro without interrupting the article.
    func downloadVoiceModel() async {
        if case .downloading = modelDownload { return }
        modelDownload = .downloading(0)
        do {
            _ = try await modelStore.download { [weak self] fraction in
                guard let model = self else { return }
                Task { @MainActor in
                    guard case .downloading = model.modelDownload else { return }
                    model.modelDownload = .downloading(fraction)
                }
            }
            modelDownload = .idle
            await loadSpeechEngine()
        } catch {
            modelDownload = Task.isCancelled ? .idle : .failed(error.localizedDescription)
        }
    }

    // MARK: - Shared URL from Extension

    private let appGroupID = "group.com.test.mier.hello"
    private let sharedURLKey = "SharedURL"
    @Published var pendingSharedURL: String?

    func checkForSharedURL() {
        let defaults = UserDefaults(suiteName: appGroupID)
        if let url = defaults?.string(forKey: sharedURLKey), !url.isEmpty {
            defaults?.removeObject(forKey: sharedURLKey)
            defaults?.synchronize()
            pendingSharedURL = url
        }
    }

    func handleOpenURL(_ url: URL) {
        guard ["pagehum", "speechly"].contains(url.scheme ?? ""), url.host == "open",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let urlParam = components.queryItems?.first(where: { $0.name == "url" })?.value else {
            return
        }
        pendingSharedURL = urlParam
    }

    func loadPendingSharedURL() async {
        guard let url = pendingSharedURL else { return }
        pendingSharedURL = nil
        await loadURL(url)
    }

    // MARK: - Content Loading

    func loadURL(_ urlString: String) async {
        var cleaned = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.hasPrefix("http://") && !cleaned.hasPrefix("https://") {
            cleaned = "https://" + cleaned
        }
        guard let url = URL(string: cleaned) else { errorMessage = String(localized: "Invalid URL"); return }
        await load(from: .url(url))
    }

    func loadPDF(_ url: URL) async { await load(from: .pdf(url)) }

    func loadText(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = String(localized: "Please enter some text"); return
        }
        await load(from: .text(text))
    }

    private func load(from source: ContentSource) async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        listeningQueue.end()
        if content != nil { saveProgressNow() }
        stop()
        do {
            content = try await extractContent(from: source)
            if let content {
                prepare(content)
                saveToPlaylist(content: content, source: source)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Shared library routing for individual opens and continuous listening.
    @discardableResult
    func openLibraryItem(_ item: PlaylistItem, preservingQueue: Bool = false, forceReload: Bool = false) -> Bool {
        if !preservingQueue { listeningQueue.end() }
        if !forceReload, currentPlaylistItemID == item.persistentModelID, progress < 1 { return true }
        if content != nil { saveProgressNow() }
        let completed = item.progressPercent >= 1 || item.status == PlaylistItem.Status.completed.rawValue
        let resumeIndex = completed ? 0 : item.lastSentenceIndex
        let resumeOffset = completed ? 0 : item.playbackTextOffset
        stop()
        errorMessage = nil
        let source: ContentSource
        if item.sourceType == "url", let value = item.sourceURL, let url = URL(string: value) { source = .url(url) }
        else { source = .text(item.fullText) }
        content = ReadingContent(title: item.title, body: item.fullText, source: source)
        currentPlaylistItemID = item.persistentModelID
        prepareTextPublic(item.fullText, resumeAt: resumeIndex, textOffset: resumeOffset)
        guard !sentences.isEmpty else {
            errorMessage = "This article has no readable text."
            return false
        }
        saveProgressNow()
        return true
    }

    private func extractContent(from source: ContentSource) async throws -> ReadingContent {
        guard case .url = source else {
            return try await extractor.extract(from: source)
        }

        let completion = ContentLoadContinuationBox<ReadingContent>()
        let extractionTask = Task { @MainActor in
            do {
                let content = try await extractor.extract(from: source)
                completion.resume(returning: content)
            } catch {
                completion.resume(throwing: error)
            }
        }
        let timeout = contentLoadTimeout
        let timeoutTask = Task.detached {
            do {
                try await Task.sleep(for: timeout)
                extractionTask.cancel()
                completion.resume(throwing: ContentLoadError.timedOut)
            } catch {}
        }
        defer {
            extractionTask.cancel()
            timeoutTask.cancel()
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completion.set(continuation)
            }
        } onCancel: {
            extractionTask.cancel()
            timeoutTask.cancel()
            completion.resume(throwing: CancellationError())
        }
    }

    func prepareTextPublic(
        _ text: String,
        resumeAt sentenceIndex: Int = 0,
        textOffset: Int? = nil
    ) {
        prepareText(text)
        let resumeIndex = textOffset.map(sentenceIndex(forTextOffset:)) ?? sentenceIndex
        if resumeIndex > 0 && resumeIndex < sentences.count {
            currentSentenceIndex = resumeIndex
            progress = Double(resumeIndex) / Double(sentences.count)
        }
    }

    private func prepareText(_ text: String) {
        fullText = text
        refreshOfflineAudioIdentity()
        if let saved = offlineStore.readyRequest(textID: currentTextID, preferredVoice: selectedVoice) {
            applyOfflineSegments(saved)
            return
        }
        // Lift code blocks out of the spoken stream. Bodies with no markers (everything saved
        // before this feature) segment to exactly `splitIntoSentences(text)`, so stored
        // `lastSentenceIndex` values stay valid.
        let segmented = ArticleSegmenter.segment(text, splitProse: Self.splitIntoSentences)
        sentences = segmented.sentences
        codeBlocks = segmented.codeBlocks
        sentenceStartOffsetsUTF16 = segmented.sentenceStartOffsetsUTF16
        currentSentenceIndex = 0
        progress = 0
        audioCache = [:]; skippedSentences = []
    }

    private func prepare(_ content: ReadingContent) {
        guard let document = content.readerDocument else {
            prepareText(content.body)
            return
        }

        fullText = document.plainText
        refreshOfflineAudioIdentity()
        if let saved = offlineStore.readyRequest(textID: currentTextID, preferredVoice: selectedVoice) {
            applyOfflineSegments(saved)
            return
        }
        let segmented = ReaderDocumentSentenceProjector.segment(
            document,
            splitProse: Self.splitIntoSentences
        )
        sentences = segmented.sentences
        codeBlocks = segmented.codeBlocks
        sentenceStartOffsetsUTF16 = segmented.sentenceStartOffsetsUTF16
        currentSentenceIndex = 0
        progress = 0
        audioCache = [:]; skippedSentences = []
    }

    // MARK: - Code blocks

    func codeBlock(at index: Int) -> CodeBlock? { codeBlocks[index] }

    /// Text to search for when highlighting the current sentence inside the live page in
    /// `WebReaderView`. For a code block the announcement doesn't exist in the DOM, so hand back a
    /// real line of the source instead and let the page's `<pre>` light up.
    func highlightNeedle(at index: Int) -> String? {
        guard index >= 0, index < sentences.count else { return nil }
        if let block = codeBlocks[index] { return block.firstSubstantialLine }
        return sentences[index]
    }

    // MARK: - Save for Later

    func importLatestTechBlogs(using discovery: any TechBlogDiscovering = TechBlogDiscovery()) async {
        guard !isLoading else { return }
        errorMessage = nil
        importResult = nil
        techBlogMessage = nil
        guard let ctx = modelContext else {
            errorMessage = "The library is not ready. Please try again."
            return
        }
        let settings = techBlogSettings.validated
        isLoading = true
        importProgress = "Finding matching articles on Hacker News…"
        defer { isLoading = false; importProgress = nil }
        do {
            let result = try await discovery.discover(settings: settings)
            try Task.checkCancellation()
            // Exclude saved articles and duplicate submissions before applying the import cap.
            let urls = TechBlogDiscovery.unsaved(result.stories, savedKeys: try libraryURLKeys(ctx)).map(\.url)
            let warning = result.failedItemCount == 0 ? "" : " " + Self.uncheckedStoriesWarning(result.failedItemCount)
            guard !urls.isEmpty else {
                techBlogMessage = (result.stories.isEmpty
                    ? "No articles matched this scan. Try scanning more stories or widening your filters."
                    : "All matching articles are already in your library.") + warning
                return
            }
            techBlogMessage = "Found \(urls.count) new matching \(urls.count == 1 ? "article" : "articles")." + warning
            _ = await performURLImport(Array(urls.prefix(settings.importLimit)))
        } catch is CancellationError {
            techBlogMessage = "Article discovery cancelled."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Loads matching stories for the user to choose from; nothing is imported.
    func loadTechBlogStories(using discovery: any TechBlogDiscovering = TechBlogDiscovery()) async {
        guard !isLoading else { return }
        errorMessage = nil
        importResult = nil
        techBlogMessage = nil
        guard let ctx = modelContext else {
            errorMessage = "The library is not ready. Please try again."
            return
        }
        isLoading = true
        importProgress = "Loading Hacker News stories…"
        defer { isLoading = false; importProgress = nil }
        do {
            let result = try await discovery.discover(settings: techBlogSettings.validated)
            try Task.checkCancellation()
            savedTechBlogKeys = try libraryURLKeys(ctx)
            techBlogStories = result.stories
            if result.failedItemCount > 0 { techBlogMessage = Self.uncheckedStoriesWarning(result.failedItemCount) }
        } catch {
            // Closing the browser cancels loading; that isn't an error worth showing.
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }

    func importTechBlogStories(_ stories: [TechBlogStory]) async {
        guard !isLoading, !stories.isEmpty else { return }
        errorMessage = nil
        importResult = nil
        techBlogMessage = nil
        _ = await performURLImport(stories.map(\.url))
    }

    func isInLibrary(_ story: TechBlogStory) -> Bool {
        savedTechBlogKeys.contains(URLImportParser.key(for: story.url))
    }

    private func libraryURLKeys(_ ctx: ModelContext) throws -> Set<String> {
        Set(try ctx.fetch(FetchDescriptor<PlaylistItem>()).compactMap { item in
            item.sourceURL.flatMap(URL.init(string:)).map { URLImportParser.key(for: $0) }
        })
    }

    private static func uncheckedStoriesWarning(_ count: Int) -> String {
        "Couldn’t check \(count) HN \(count == 1 ? "story" : "stories"); try again to refresh."
    }

    func saveForLater(_ urlString: String) async {
        await importURLs(from: urlString)
    }

    @discardableResult
    func importURLs(from text: String) async -> URLImportResult? {
        guard !isLoading else { return nil }
        errorMessage = nil
        importResult = nil
        techBlogMessage = nil
        let urls = URLImportParser.urls(in: text)
        guard !urls.isEmpty else {
            errorMessage = "No web links found. Paste URLs separated by spaces, new lines, or commas."
            return nil
        }
        return await performURLImport(urls)
    }

    private func performURLImport(_ urls: [URL]) async -> URLImportResult? {
        guard let ctx = modelContext else {
            errorMessage = "The library is not ready. Please try again."
            return nil
        }
        isLoading = true
        defer { isLoading = false; importProgress = nil }
        var result = URLImportResult()
        do {
            var savedURLs = try libraryURLKeys(ctx)
            for (index, url) in urls.enumerated() {
                importProgress = "Importing \(index + 1) of \(urls.count)…"
                let key = URLImportParser.key(for: url)
                if savedURLs.contains(key) {
                    result.skipped += 1
                    if urls.count == 1 {
                        result.singleItem = try ctx.fetch(FetchDescriptor<PlaylistItem>()).first {
                            $0.sourceURL.flatMap(URL.init(string:)).map { URLImportParser.key(for: $0) } == key
                        }
                    }
                    continue
                }
                do {
                    try Task.checkCancellation()
                    let extracted = try await extractContent(from: .url(url))
                    try Task.checkCancellation()
                    let item = PlaylistItem(title: extracted.title, sourceURL: url.absoluteString,
                                            sourceType: "url", fullText: extracted.body,
                                            status: PlaylistItem.Status.queued.rawValue)
                    ctx.insert(item)
                    do { try ctx.save() }
                    catch { ctx.delete(item); throw error }
                    savedURLs.insert(key)
                    result.imported += 1
                    if urls.count == 1 { result.singleItem = item }
                } catch {
                    result.failures.append(.init(url: url, message: error.localizedDescription))
                }
            }
            savedTechBlogKeys = savedURLs
            importResult = result
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Seek

    func seekToSentence(_ index: Int) {
        guard index >= 0 && index < sentences.count else { return }
        let wasPlaying = isPlaying

        if wasPlaying {
            accumulateListeningTime()
        }

        // Tear down any in-flight scheduling/generation. Cached audio from the old position is
        // dropped (regeneration is required after a seek until A1's disk cache lands).
        scheduler.stop()
        generationTask?.cancel()
        generationTask = nil
        stopWordTimer()
        audioCache = [:]; skippedSentences = []

        // A seek while paused collapses to a stopped position, so the next play() does a fresh start.
        isPaused = false
        currentSentenceIndex = index
        currentTokenIndex = -1
        currentWordText = ""
        pauseElapsed = 0
        progress = Double(index) / Double(sentences.count)
        saveProgressNow()

        if wasPlaying {
            isPreparing = true
            isPlaying = false
            ensureAudioSessionActive()
            if !audioEngine.isRunning { try? audioEngine.start() }
            startPipeline()
            scheduler.start(from: index)
        }
    }

    private func saveToPlaylist(content: ReadingContent, source: ContentSource) {
        guard let ctx = modelContext else { return }
        let sourceType: String
        var sourceURL: String?
        switch source {
        case .url(let url):
            sourceType = "url"
            sourceURL = url.absoluteString
        case .pdf(let url):
            sourceType = "pdf"
            sourceURL = url.lastPathComponent
        case .text:
            sourceType = "text"
        }
        let item = PlaylistItem(title: content.title, sourceURL: sourceURL, sourceType: sourceType, fullText: content.body)
        ctx.insert(item)
        try? ctx.save()
        currentPlaylistItemID = item.persistentModelID
    }

    func saveProgressNow() {
        guard let ctx = modelContext, let id = currentPlaylistItemID else { return }
        guard let item = ctx.model(for: id) as? PlaylistItem else { return }
        item.progressPercent = progress
        item.lastSentenceIndex = currentSentenceIndex
        item.playbackTextOffset = progress >= 1
            ? fullText.utf16.count
            : playbackTextOffset(for: currentSentenceIndex)
        item.lastPlayed = Date()
        if progress >= 1.0 {
            item.status = PlaylistItem.Status.completed.rawValue
        } else {
            item.status = PlaylistItem.Status.inProgress.rawValue
        }
        try? ctx.save()
        updateNowPlayingInfo()
    }

    func migrateLegacyPlaybackTextOffsets() {
        guard let modelContext,
              let items = try? modelContext.fetch(FetchDescriptor<PlaylistItem>())
        else { return }

        if LegacyPlaybackOffsetMigration.migrate(
            items: items,
            splitProse: Self.splitIntoSentences
        ) {
            try? modelContext.save()
        }
    }

    private func playbackTextOffset(for sentenceIndex: Int) -> Int {
        guard !sentenceStartOffsetsUTF16.isEmpty else { return 0 }
        guard sentenceIndex < sentenceStartOffsetsUTF16.count else { return fullText.utf16.count }
        return sentenceStartOffsetsUTF16[max(sentenceIndex, 0)]
    }

    private func sentenceIndex(forTextOffset textOffset: Int) -> Int {
        guard !sentenceStartOffsetsUTF16.isEmpty else { return 0 }
        let offset = max(textOffset, 0)
        var lowerBound = 0
        var upperBound = sentenceStartOffsetsUTF16.count

        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if sentenceStartOffsetsUTF16[middle] <= offset {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        return min(max(lowerBound - 1, 0), sentences.count - 1)
    }

    // MARK: - Listening Time Tracking

    private func accumulateListeningTime() {
        guard let start = listeningSessionStart else { return }
        listeningAccumulator += Date().timeIntervalSince(start) * Double(speed)
        listeningSessionStart = nil
    }

    private func saveListeningTime() {
        guard listeningAccumulator > 0, let ctx = modelContext else { return }
        let today = ListeningRecord.dayFormatter.string(from: Date())
        let descriptor = FetchDescriptor<ListeningRecord>(
            predicate: #Predicate { $0.dateString == today }
        )
        if let existing = try? ctx.fetch(descriptor).first {
            existing.secondsListened += listeningAccumulator
        } else {
            ctx.insert(ListeningRecord(date: Date(), secondsListened: listeningAccumulator))
        }
        try? ctx.save()
        listeningAccumulator = 0
    }

    private func startListeningSaveTimer() {
        stopListeningSaveTimer()
        listeningSaveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                self.accumulateListeningTime()
                self.saveListeningTime()
                self.listeningSessionStart = Date()
            }
        }
    }

    private func stopListeningSaveTimer() {
        listeningSaveTimer?.invalidate()
        listeningSaveTimer = nil
    }

    // MARK: - Playback Controls

    private func refreshOfflineAudioIdentity() {
        currentTextID = fullText.isEmpty ? "" : OfflineAudioRequest.textIdentifier(fullText)
        currentOfflineAudioID = fullText.isEmpty ? nil : OfflineAudioRequest.identifier(textID: currentTextID, voice: selectedVoice)
        activeOfflineAudioID = nil
    }

    func offlineRequest(for item: PlaylistItem) -> OfflineAudioRequest {
        let id = offlineAudioID(for: item)
        if let existing = offlineStore.record(id) { return existing.request }
        if item.persistentModelID == currentPlaylistItemID, item.fullText == fullText {
            return currentOfflineRequest()
        }
        let segmented = ArticleSegmenter.segment(item.fullText, splitProse: Self.splitIntoSentences)
        return OfflineAudioRequest(text: item.fullText, title: item.title, voice: selectedVoice,
                                   sentences: segmented.sentences, offsets: segmented.sentenceStartOffsetsUTF16, codeBlocks: segmented.codeBlocks)
    }

    func offlineAudioID(for item: PlaylistItem) -> String {
        OfflineAudioRequest.identifier(textID: OfflineAudioRequest.textIdentifier(item.fullText), voice: selectedVoice)
    }

    private func currentOfflineRequest() -> OfflineAudioRequest {
        OfflineAudioRequest(text: fullText, title: content?.title ?? "Article", voice: selectedVoice,
                            sentences: sentences, offsets: sentenceStartOffsetsUTF16, codeBlocks: codeBlocks)
    }

    func saveAudioOffline(_ items: [PlaylistItem]) { offlineAudio.enqueue(items.map { offlineRequest(for: $0) }) }
    func saveCurrentAudioOffline() {
        guard !fullText.isEmpty else { return }
        offlineAudio.enqueue([currentOfflineRequest()])
    }

    func saveQueueAudioOffline() {
        guard let modelContext, let items = try? modelContext.fetch(FetchDescriptor<PlaylistItem>()) else { return }
        let ids = [listeningQueue.current?.id].compactMap { $0 } + listeningQueue.upcoming.map(\.id)
        saveAudioOffline(ids.compactMap { id in items.first { $0.persistentModelID == id } })
    }

    private func applyOfflineSegments(_ request: OfflineAudioRequest) {
        activeOfflineAudioID = request.id
        sentences = request.sentences
        sentenceStartOffsetsUTF16 = request.offsets
        codeBlocks = request.codeBlocks
        currentSentenceIndex = 0
        progress = 0
        audioCache = [:]; skippedSentences = []
    }

    private func activateOfflinePlayback() {
        guard let saved = offlineStore.readyRequest(textID: currentTextID, preferredVoice: selectedVoice) else { return }
        let offset = playbackTextOffset(for: currentSentenceIndex)
        if sentences != saved.sentences {
            guard !isPaused else { return }
            applyOfflineSegments(saved)
            currentSentenceIndex = sentenceIndex(forTextOffset: offset)
            progress = Double(currentSentenceIndex) / Double(max(1, sentences.count))
        }
        activeOfflineAudioID = saved.id
    }

    private func savedAudio(at index: Int) -> SentenceAudio? {
        guard let id = activeOfflineAudioID ?? currentOfflineAudioID,
              let request = offlineStore.record(id)?.request,
              request.sentences.indices.contains(index), sentences.indices.contains(index),
              request.sentences[index] == sentences[index] else { return nil }
        return offlineStore.load(id: id, index: index)
    }

    func play() {
        guard !isPlaying, !isPreparing else { return }
        activateOfflinePlayback()
        guard canPlayCurrentContent, !isPreparing else { return }
        isWaitingForOfflineAudio = false
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = true
        #endif
        if isPaused {
            ensureAudioSessionActive()
            if !audioEngine.isRunning {
                do { try audioEngine.start() } catch {
                    print("Engine restart error: \(error)")
                    isPaused = false
                    isPlaying = false
                    errorMessage = "Audio playback could not resume. \(error.localizedDescription)"
                    listeningQueue.playbackFailed(errorMessage!, at: currentSentenceIndex)
                    #if os(iOS)
                    UIApplication.shared.isIdleTimerDisabled = false
                    #endif
                    return
                }
            }
            scheduler.resume()
            isPaused = false
            isPlaying = true
            bufferStartTime = Date().addingTimeInterval(-pauseElapsed)
            startWordTimer()
            listeningSessionStart = Date()
            startListeningSaveTimer()
            return
        }
        // Cancel any existing work before starting fresh.
        generationTask?.cancel()
        generationTask = nil
        scheduler.stop()
        stopWordTimer()

        // The scheduler starts the player node, so the engine/session must be live first.
        ensureAudioSessionActive()
        if !audioEngine.isRunning {
            do { try audioEngine.start() } catch {
                print("Engine error: \(error)")
                isPlaying = false
                isPreparing = false
                errorMessage = "Audio playback could not start. \(error.localizedDescription)"
                listeningQueue.playbackFailed(errorMessage!, at: currentSentenceIndex)
                #if os(iOS)
                UIApplication.shared.isIdleTimerDisabled = false
                #endif
                return
            }
        }

        isPreparing = true
        isPlaying = false
        isPaused = false
        playbackFailureCount = 0
        audioCache = [:]; skippedSentences = []
        startPipeline()
        scheduler.start(from: currentSentenceIndex)
        updateNowPlayingInfo()
    }

    func pause() {
        isWaitingForOfflineAudio = false
        listeningQueue.pausePendingAdvance()
        if let start = bufferStartTime {
            pauseElapsed = Date().timeIntervalSince(start)
        }
        scheduler.pause()
        isPaused = true
        isPlaying = false
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
        stopWordTimer()
        accumulateListeningTime()
        saveListeningTime()
        stopListeningSaveTimer()
        saveProgressNow()
    }

    func stop() {
        isWaitingForOfflineAudio = false
        generationTask?.cancel()
        generationTask = nil
        scheduler.stop()
        isPreparing = false
        isPlaying = false
        isPaused = false
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
        currentSentenceIndex = 0
        currentTokenIndex = -1
        currentWordText = ""
        progress = 0
        playbackFailureCount = 0
        audioCache = [:]; skippedSentences = []
        stopWordTimer()
        accumulateListeningTime()
        saveListeningTime()
        stopListeningSaveTimer()
        #if os(iOS)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #endif
    }

    func togglePlayback() {
        if listeningQueue.failure != nil, listeningQueue.isManaging(currentPlaylistItemID) {
            listeningQueue.retry()
            return
        }
        if isPreparing {
            stop()
        } else {
            isPlaying ? pause() : play()
        }
    }

    func restartFromBeginning() {
        guard canPlayCurrentContent else { return }
        stop()
        saveProgressNow()
        play()
    }

    func skipForward() {
        let target = sentenceIndexBySkipping(seconds: 20, forward: true)
        seekToSentence(target)
    }

    func skipBackward() {
        let target = sentenceIndexBySkipping(seconds: 20, forward: false)
        seekToSentence(target)
    }

    private static let estimatedCharsPerSecond: Double = 13

    private func sentenceIndexBySkipping(seconds: Double, forward: Bool) -> Int {
        let charBudget = seconds * Self.estimatedCharsPerSecond
        var accumulated: Double = 0
        var index = currentSentenceIndex

        if forward {
            while index < sentences.count - 1 && accumulated < charBudget {
                accumulated += Double(sentences[index].count)
                index += 1
            }
        } else {
            while index > 0 && accumulated < charBudget {
                index -= 1
                accumulated += Double(sentences[index].count)
            }
        }
        return index
    }

    func cleanup() {
        stop()
    }



    // MARK: - Now Playing & Remote Controls

    #if os(iOS)
    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayback() }
            return .success
        }

        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [20]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipForward() }
            return .success
        }

        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [20]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipBackward() }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = content?.title ?? "Pagehum"
        info[MPMediaItemPropertyArtist] = "Pagehum"
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(speed) : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0

        let totalSentences = Double(max(sentences.count, 1))
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(currentSentenceIndex)
        info[MPMediaItemPropertyPlaybackDuration] = totalSentences

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func ensureAudioSessionActive() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Only apply the category if it drifted (e.g. another app changed it while we were
            // suspended). Re-setting an already-correct active session hitches the main thread and
            // can trigger -50 errors on some devices.
            if session.category != .playback || session.mode != .spokenAudio {
                try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
            }
            try session.setActive(true)
        } catch {
            print("Audio session re-activation error: \(error)")
        }
    }

    private func setupAudioSessionObservers() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let info = notification.userInfo,
                      let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }

                switch type {
                case .began:
                    if self.isPlaying { self.pause() }
                case .ended:
                    guard let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                    if options.contains(.shouldResume) { self.play() }
                @unknown default:
                    break
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self,
                      let info = notification.userInfo,
                      let reasonRaw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }

                if reason == .oldDeviceUnavailable && self.isPlaying {
                    self.pause()
                }
            }
        }

        // Restart audio engine if hardware routing or screen lock reconfigures audio hardware
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isPlaying && !self.audioEngine.isRunning {
                    self.ensureAudioSessionActive()
                    try? self.audioEngine.start()
                }
            }
        }

        // Intercept as soon as app begins resigning active to stop starting new GPU work
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // NotificationCenter delivers on the main queue. Finish the barrier
            // inside this callback; an unstructured Task can run after suspension.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isAppInBackground = true
                self.offlineAudio.suspend()
                KokoroSpeechEngine.drainAndEvictGPU()
            }
        }

        // Track background state and persist playback/stats when entering background.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isAppInBackground = true
                self.saveProgressNow()
                self.accumulateListeningTime()
                self.saveListeningTime()
            }
        }

        // If iOS deactivated our session while we were paused/backgrounded, reactivate it and
        // restart the engine on foreground so the next play() call doesn't silently fail.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                KokoroSpeechEngine.resumeGPUWork()
                self.isAppInBackground = false
                self.offlineAudio.resume()
                self.ensureAudioSessionActive()
                if self.isWaitingForOfflineAudio {
                    self.isWaitingForOfflineAudio = false
                    self.isPaused = false
                    self.play()
                }
                if self.isPlaying {
                    if !self.audioEngine.isRunning {
                        try? self.audioEngine.start()
                    }
                    if self.generationTask == nil {
                        self.startPipeline()
                    }
                }
            }
        }
    }
    #else
    private func updateNowPlayingInfo() {}
    private func ensureAudioSessionActive() {}
    #endif

    // MARK: - Pipeline: pre-generate audio concurrently

    private func startPipeline() {
        generationTask?.cancel()
        if let id = activeOfflineAudioID, offlineStore.record(id)?.isReady == true {
            generationTask = nil
            return // The normal scheduler reads saved clips on demand; no synthesis or deep PCM cache.
        }
        generationTask = Task { [weak self] in
            guard let self else { return }
            let format = self.audioFormat
            let voice = self.selectedVoice

            var genIndex = self.currentSentenceIndex
            while genIndex < self.sentences.count && !Task.isCancelled {
                if self.audioCache[genIndex] != nil {
                    genIndex += 1
                    await Task.yield()
                    continue
                }

                let text = self.sentences[genIndex]
                let voiceKey = voice + ".npy"

                // Explicit offline saves survive normal cache eviction and are preferred.
                if let diskAudio = self.savedAudio(at: genIndex) ?? AudioDiskCache.shared.load(text: text, voiceKey: voiceKey) {
                    self.audioCache[genIndex] = diskAudio
                    self.scheduler.notifyAvailable()
                    genIndex += 1
                    await Task.yield()
                    continue
                }

                // If in background and not cached on disk, pause generation until foregrounded.
                // Do NOT mark as skipped - wait for foreground so Kokoro can synthesize it.
                if !self.canRunSpeechWork {
                    while !self.canRunSpeechWork && !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                    guard !Task.isCancelled else { break }
                    continue
                }

                // In the foreground, allow deep lookahead pre-caching
                while genIndex - self.currentSentenceIndex >= self.lookaheadCount && !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                guard !Task.isCancelled else { break }

                while self.isSynthesisInFlight && !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(20))
                }
                guard !Task.isCancelled else { break }

                self.isGenerating = self.audioCache[self.currentSentenceIndex] == nil

                let audio: SentenceAudio?
                self.isSynthesisInFlight = true
                if let audioGenerator = self.audioGenerator {
                    audio = await audioGenerator(text, format)
                } else {
                    audio = await self.generateSentenceAudio(for: text, format: format, voice: voice)
                }
                self.isSynthesisInFlight = false

                guard !Task.isCancelled else { break }
                if let audio {
                    self.audioCache[genIndex] = audio
                } else {
                    if !self.canRunSpeechWork {
                        continue
                    }
                    self.skippedSentences.insert(genIndex)
                    self.playbackFailureCount = self.skippedSentences.count
                    if self.listeningQueue.isManaging(self.currentPlaylistItemID) {
                        self.listeningQueue.playbackFailed(
                            "Audio couldn’t be generated for this article. Retry or skip it to continue.",
                            at: min(self.currentSentenceIndex, genIndex)
                        )
                        break
                    }
                }
                self.isGenerating = false
                // Let the scheduler advance if it was waiting on this sentence.
                self.scheduler.notifyAvailable()
                genIndex += 1
            }
            self.isGenerating = false
        }
    }

    // MARK: - Scheduler callbacks

    private func handleWaitingForAudio(at index: Int) {
        guard !canRunSpeechWork, !isPaused else { return }
        currentSentenceIndex = index
        progress = Double(index) / Double(max(1, sentences.count))
        pause()
        isPreparing = false
        isWaitingForOfflineAudio = true
    }

    /// A sentence just became audible. Sync the reader's current index, word-highlight timing, and
    /// persisted progress. Invoked by `GaplessSentenceScheduler` on the main actor.
    private func handleSentenceStarted(index: Int, audio: SentenceAudio) {
        let beganPlayback = isPreparing
        isPreparing = false
        isPlaying = true
        currentSentenceIndex = index
        currentTokens = audio.tokens
        currentTokenIndex = -1
        currentWordText = ""
        pauseElapsed = 0
        // For AAC cache hits whose priming couldn't be trimmed, nudge the clock forward so the word
        // highlight stays aligned with the (slightly delayed) audio.
        bufferStartTime = Date().addingTimeInterval(audio.leadingSilence)
        progress = Double(index) / Double(max(sentences.count, 1))

        // Evict audio that has already played; the player retains buffers it is still using.
        for key in audioCache.keys where key < index { audioCache.removeValue(forKey: key) }

        startWordTimer()
        if beganPlayback {
            listeningSessionStart = Date()
            startListeningSaveTimer()
        }
        saveProgressNow()
    }

    /// The last schedulable sentence finished playing.
    private func handlePlaybackFinished() {
        let completedPlayback = !isPreparing
        isPreparing = false
        isPlaying = false
        isPaused = false
        currentTokenIndex = -1
        if completedPlayback {
            progress = 1.0
        }
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
        stopWordTimer()
        accumulateListeningTime()
        saveListeningTime()
        stopListeningSaveTimer()
        saveProgressNow()
        listeningQueue.articleFinished()
    }

    // MARK: - Word-level tracking

    private func startWordTimer() {
        stopWordTimer()
        wordTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateWordHighlight() }
        }
    }

    private func stopWordTimer() {
        wordTimer?.invalidate()
        wordTimer = nil
    }

    private func updateWordHighlight() {
        guard let tokens = currentTokens, !tokens.isEmpty,
              let startTime = bufferStartTime else { return }

        // Wall-clock elapsed * speed = position in original 1.0x audio
        let elapsed = Date().timeIntervalSince(startTime) * Double(speed)

        var newIndex = currentTokenIndex
        for (i, token) in tokens.enumerated() {
            guard let start = token.start else { continue }
            if elapsed >= start {
                newIndex = i
            }
        }

        if newIndex != currentTokenIndex {
            currentTokenIndex = newIndex
            if newIndex >= 0 && newIndex < tokens.count {
                currentWordText = tokens[newIndex].text
            }
        }
    }

    // MARK: - Audio generation

    private func generateSentenceAudio(for text: String, format: AVAudioFormat, voice: String, allowFallback: Bool = true) async -> SentenceAudio? {
        let voiceKey = voice + ".npy"
        let cache = AudioDiskCache.shared
        // A disk cache hit skips synthesis entirely; file I/O stays off the main thread and requires no GPU.
        let cached = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: cache.load(text: text, voiceKey: voiceKey))
            }
        }
        if let cached { return cached }

        // When the app is in the background or resigning active on iOS, NEVER invoke Kokoro (Metal GPU).
        // Submitting Metal command buffers while backgrounded triggers an immediate process termination
        // (SIGABRT/kIOGPUCommandBufferCallbackErrorBackgroundExecutionNotPermitted) by the iOS kernel.
        if !canRunSpeechWork {
            return nil
        }

        // Primary engine synthesis (e.g. Kokoro 82M on Apple Silicon) in the foreground
        if let engine = speechEngine, let audio = await engine.synthesize(text, voice: voice, format: format) {
            cache.store(text: text, voiceKey: voiceKey, buffer: audio.buffer, tokens: audio.tokens)
            return audio
        }

        // Foreground fallback if primary engine fails
        if allowFallback, let fallback = fallbackEngineInstance {
            let fallbackVoice = fallback.defaultVoice ?? fallback.voices.first ?? ""
            if let audio = await fallback.synthesize(text, voice: fallbackVoice, format: format) {
                return audio
            }
        }

        return nil
    }

    // MARK: - Text Splitting

    static func splitIntoSentences(_ text: String) -> [String] {
        SentenceSegmenter.splitIntoSentences(text)
    }

}

// MARK: - Gapless scheduling: audio provider

extension ReaderModel: SentenceAudioProvider {
    var sentenceCount: Int { sentences.count }

    func audioState(at index: Int) -> SentenceAudioState {
        if let audio = audioCache[index] { return .ready(audio) }
        if let audio = savedAudio(at: index) {
            audioCache[index] = audio
            return .ready(audio)
        }
        if skippedSentences.contains(index) { return .skipped }
        if index < sentences.count {
            let text = sentences[index]
            let voiceKey = selectedVoice + ".npy"
            if let cached = AudioDiskCache.shared.load(text: text, voiceKey: voiceKey) {
                audioCache[index] = cached
                return .ready(cached)
            }
        }
        return .pending
    }
}
