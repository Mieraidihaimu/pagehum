// Modified for Pagehum: unified application and command-line naming.
import AVFoundation
import Testing
@testable import Pagehum

@MainActor
struct GaplessSentenceSchedulerTests {
    @Test
    func fillsLookaheadWhenPendingAudioBecomesAvailable() {
        let firstAudio = makeAudio()
        let secondAudio = makeAudio()
        let provider = FakeAudioProvider(states: [.pending, .pending])
        let player = FakeAudioBufferPlayer()
        let scheduler = GaplessSentenceScheduler(player: player, provider: provider)
        var started: [Int] = []
        var finishedCount = 0
        scheduler.onSentenceStarted = { index, _ in started.append(index) }
        scheduler.onFinished = { finishedCount += 1 }

        scheduler.start(from: 0)
        #expect(player.scheduledCount == 0)

        provider.states[0] = .ready(firstAudio)
        scheduler.notifyAvailable()
        provider.states[1] = .ready(secondAudio)
        scheduler.notifyAvailable()

        #expect(player.scheduledCount == 2)
        #expect(started == [0])

        player.completeNext()
        #expect(started == [0, 1])

        player.completeNext()
        #expect(finishedCount == 1)
    }

    @Test
    func skipsFailedSentencesAndFinishesOnce() {
        let provider = FakeAudioProvider(states: [.skipped, .skipped])
        let player = FakeAudioBufferPlayer()
        let scheduler = GaplessSentenceScheduler(player: player, provider: provider)
        var finishedCount = 0
        scheduler.onFinished = { finishedCount += 1 }

        scheduler.start(from: 0)
        scheduler.notifyAvailable()

        #expect(player.scheduledCount == 0)
        #expect(finishedCount == 1)
    }

    @Test
    func pendingAudioDoesNotBecomeAudibleUntilPausedSchedulerResumes() {
        let provider = FakeAudioProvider(states: [.pending])
        let player = FakeAudioBufferPlayer()
        let scheduler = GaplessSentenceScheduler(player: player, provider: provider)
        var started: [Int] = []
        scheduler.onSentenceStarted = { index, _ in started.append(index) }

        scheduler.start(from: 0)
        scheduler.pause()
        provider.states[0] = .ready(makeAudio())
        scheduler.notifyAvailable()

        #expect(player.scheduledCount == 1)
        #expect(started.isEmpty)
        #expect(!player.isPlaying)

        scheduler.resume()

        #expect(started == [0])
        #expect(player.isPlaying)
    }

    private func makeAudio() -> SentenceAudio {
        let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        buffer.frameLength = 1
        return SentenceAudio(buffer: buffer, tokens: nil)
    }
}

@MainActor
private final class FakeAudioProvider: SentenceAudioProvider {
    var states: [SentenceAudioState]

    init(states: [SentenceAudioState]) {
        self.states = states
    }

    var sentenceCount: Int { states.count }

    func audioState(at index: Int) -> SentenceAudioState {
        states[index]
    }
}

private final class FakeAudioBufferPlayer: AudioBufferPlayer {
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