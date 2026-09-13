import AVFoundation

/// Minimal abstraction over the object that actually plays PCM buffers.
///
/// This is the *only* AVFoundation dependency of ``GaplessSentenceScheduler``. Keeping it behind a
/// protocol lets the scheduler be unit-tested with a mock player — no `AVAudioEngine`, no device,
/// no MLX.
///
/// Implementations must invoke `onComplete` **on the main thread** so the `@MainActor` scheduler can
/// mutate its state safely and in completion order.
protocol AudioBufferPlayer: AnyObject {
    var isPlaying: Bool { get }

    /// Schedule a buffer to play after any previously-scheduled buffers (gapless).
    /// - Parameter onComplete: invoked once, on the main thread, when the buffer finishes playing.
    func schedule(_ buffer: AVAudioPCMBuffer, onComplete: @escaping () -> Void)

    func play()
    func pause()
    func stop()
}

/// Production adapter backed by a real `AVAudioPlayerNode`.
///
/// The node fires completion handlers on an internal queue; this adapter hops them to the main
/// thread so the scheduler observes them in order and can touch main-actor state.
final class AVAudioPlayerNodeAdapter: AudioBufferPlayer {

    private let node: AVAudioPlayerNode

    init(_ node: AVAudioPlayerNode) {
        self.node = node
    }

    var isPlaying: Bool { node.isPlaying }

    func schedule(_ buffer: AVAudioPCMBuffer, onComplete: @escaping () -> Void) {
        // `.dataPlayedBack` fires when the audio has actually finished playing (not merely when the
        // node has consumed the buffer), which keeps `onSentenceStarted` timing aligned with what
        // the listener hears.
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
            DispatchQueue.main.async { onComplete() }
        }
    }

    func play()  { node.play() }
    func pause() { node.pause() }
    func stop()  { node.stop() }
}
