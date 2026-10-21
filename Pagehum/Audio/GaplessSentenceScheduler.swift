// Modified for Pagehum: unified application and command-line naming.
import Foundation
import AVFoundation

/// The audio state of a single sentence at a point in time, as seen by the scheduler.
enum SentenceAudioState {
    /// Generated and ready to schedule.
    case ready(SentenceAudio)
    /// Not generated yet — the scheduler must wait for ``GaplessSentenceScheduler/notifyAvailable()``.
    case pending
    /// Generation failed or the sentence was intentionally skipped — advance past it.
    case skipped
}

/// Read-only source of generated sentence audio, addressed by sentence position.
///
/// In production this is backed by `ReaderModel`'s in-memory cache; in tests it is a trivial stub.
/// `@MainActor` because the production implementation (and its backing cache) is main-actor state.
@MainActor
protocol SentenceAudioProvider: AnyObject {
    var sentenceCount: Int { get }
    func audioState(at index: Int) -> SentenceAudioState
}

/// Schedules sentence buffers for **gapless** playback.
///
/// `AVAudioPlayerNode` plays consecutively-scheduled buffers with no gap, so this component keeps up
/// to ``maxInFlight`` buffers scheduled on the player at all times. When the head buffer finishes,
/// the next one is *already* playing; the completion is used to advance the audible cursor and top
/// the queue back up.
///
/// ### Responsibilities
/// - Decide *which* sentence to schedule next and *how many* to keep queued (gaplessness).
/// - Track the currently-audible sentence and emit ``onSentenceStarted`` / ``onFinished``.
/// - Handle `skipped` / `pending` sentences and end-of-content.
///
/// ### Explicitly not its job
/// - Generating audio, owning the engine/session, word highlighting, persistence, cache eviction.
///   Those live in `ReaderModel` and react to the callbacks below.
///
/// All methods must be called on the main actor. The component is clock-free and deterministic,
/// which makes it fully unit-testable with a mock ``AudioBufferPlayer`` and stub
/// ``SentenceAudioProvider`` (see `docs/IMPROVEMENT_PLAN.md`).
@MainActor
final class GaplessSentenceScheduler {

    // MARK: - Dependencies

    private let player: AudioBufferPlayer
    private unowned let provider: SentenceAudioProvider
    private let maxInFlight: Int

    // MARK: - Outputs

    /// Fired when a sentence becomes audible (its index + audio, whose `tokens` drive word
    /// highlighting). Use to sync the current index, word highlighting, progress, and persistence.
    /// Passing `SentenceAudio` (an app-module type) keeps the scheduler free of any Kokoro/MLX
    /// dependency, so it stays unit-testable off-device.
    var onSentenceStarted: ((Int, SentenceAudio) -> Void)?

    /// Fired exactly once when the last schedulable sentence has finished playing.
    var onFinished: (() -> Void)?

    // MARK: - State

    /// Next sentence index the scheduler will attempt to schedule.
    private var nextToSchedule = 0
    /// Indices scheduled on the player and not yet completed, in play order. `first` is audible.
    private var inFlight: [Int] = []
    /// Audio for in-flight sentences, so it can be handed to `onSentenceStarted` at the right time.
    private var audioByIndex: [Int: SentenceAudio] = [:]
    /// The most recently announced audible index, to avoid duplicate `onSentenceStarted` calls.
    private var announcedHead: Int?
    private var isActive = false
    private var isPaused = false

    /// Optional silence buffer scheduled between sentences to keep the player rendering while the
    /// generation pipeline catches up. Without this, the player queue drains → iOS suspends the app
    /// (even under the audio background mode) → synthesis stalls → deadlock.
    private let silenceBridgeBuffer: AVAudioPCMBuffer?
    /// Silence buffers currently scheduled on the player. Counted separately from `inFlight` so
    /// they don't appear as audible sentences.
    private var silenceInFlight = 0
    /// Cap consecutive silence bridges so a truly stalled pipeline surfaces instead of playing
    /// silence indefinitely.
    private var consecutiveSilenceBridges = 0
    private let maxConsecutiveSilenceBridges = 30
    /// Tracks whether at least one real sentence buffer has been scheduled in the current session.
    /// Silence bridging must only occur between sentences after playback has begun, never before.
    private var hasScheduledSentence = false

    /// The sentence currently being heard, if any. Exposed for diagnostics/tests.
    var audibleIndex: Int? { inFlight.first }

    // MARK: - Init

    init(
        player: AudioBufferPlayer,
        provider: SentenceAudioProvider,
        maxInFlight: Int = 3,
        silenceBridgeBuffer: AVAudioPCMBuffer? = nil
    ) {
        self.player = player
        self.provider = provider
        self.maxInFlight = max(2, maxInFlight)   // need ≥2 buffers queued for gapless transitions
        self.silenceBridgeBuffer = silenceBridgeBuffer
    }

    // MARK: - Control

    /// Begin (or restart) playback at `index`.
    func start(from index: Int) {
        reset()
        isActive = true
        nextToSchedule = index
        player.play()
        refill()
        syncAudibleHead()
    }

    /// Pause playback. Scheduled buffers and their pending completions are retained.
    func pause() {
        guard isActive else { return }
        isPaused = true
        player.pause()
    }

    /// Resume after ``pause()``. Scheduled buffers continue playing; no re-scheduling needed.
    func resume() {
        guard isActive else { return }
        isPaused = false
        player.play()
        syncAudibleHead()
    }

    /// Stop playback, flush scheduled buffers, and clear all state.
    func stop() {
        isActive = false
        player.stop()
        reset()
    }

    /// Called by the generation pipeline whenever a sentence becomes `ready` or `skipped`, so a
    /// scheduler that was waiting on a `pending` sentence can make progress.
    func notifyAvailable() {
        guard isActive else { return }
        refill()
        syncAudibleHead()
    }

    // MARK: - Internals

    private func reset() {
        nextToSchedule = 0
        inFlight.removeAll()
        audioByIndex.removeAll()
        announcedHead = nil
        isPaused = false
        silenceInFlight = 0
        consecutiveSilenceBridges = 0
        hasScheduledSentence = false
    }

    /// Schedule ready buffers until the in-flight queue is full, we run out of sentences, or we hit a
    /// `pending` sentence (which we cannot schedule past without playing out of order).
    private func refill() {
        while isActive && inFlight.count < maxInFlight && nextToSchedule < provider.sentenceCount {
            switch provider.audioState(at: nextToSchedule) {
            case .skipped:
                nextToSchedule += 1

            case .pending:
                scheduleSilenceBridgeIfNeeded()
                return   // wait for notifyAvailable()

            case .ready(let audio):
                let idx = nextToSchedule
                inFlight.append(idx)
                audioByIndex[idx] = audio
                nextToSchedule += 1
                consecutiveSilenceBridges = 0
                hasScheduledSentence = true
                player.schedule(audio.buffer) { [weak self] in
                    // Adapter guarantees this runs on the main thread.
                    MainActor.assumeIsolated { self?.handleCompletion(of: idx) }
                }
            }
        }

        if isActive && inFlight.isEmpty && silenceInFlight == 0 && nextToSchedule >= provider.sentenceCount {
            finish()
        }
    }

    /// Keep the player rendering by scheduling a silence buffer while we wait on synthesis.
    /// Only fires when the sentence queue is empty (or nearly so) and we haven't already bridged.
    private func scheduleSilenceBridgeIfNeeded() {
        guard isActive,
              hasScheduledSentence,
              let silence = silenceBridgeBuffer,
              inFlight.isEmpty,
              silenceInFlight == 0,
              consecutiveSilenceBridges < maxConsecutiveSilenceBridges
        else { return }
        silenceInFlight += 1
        consecutiveSilenceBridges += 1
        player.schedule(silence) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.silenceInFlight -= 1
                guard self.isActive else { return }
                self.refill()
                self.syncAudibleHead()
            }
        }
    }

    /// Invoked (on the main thread) when a scheduled buffer finishes playing.
    private func handleCompletion(of index: Int) {
        guard isActive else { return }   // ignore late completions after stop()

        // Completions arrive in schedule order, so the finished buffer is normally the head.
        if inFlight.first == index {
            inFlight.removeFirst()
        } else {
            inFlight.removeAll { $0 == index }
        }
        audioByIndex[index] = nil

        refill()
        syncAudibleHead()
    }

    /// Emit ``onSentenceStarted`` whenever the audible head changes to a new sentence.
    private func syncAudibleHead() {
        guard !isPaused else { return }
        let head = inFlight.first
        guard head != announcedHead else { return }
        announcedHead = head
        if let head, let audio = audioByIndex[head] {
            onSentenceStarted?(head, audio)
        }
    }

    private func finish() {
        guard isActive else { return }
        isActive = false
        onFinished?()
    }
}
