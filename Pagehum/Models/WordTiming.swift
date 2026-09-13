import Foundation

/// A single word's on-screen text plus its audio-aligned timestamps (seconds, relative to the
/// sentence's audio at speed 1.0).
///
/// This is our own `Codable`, MLX-free stand-in for the only parts of `MToken` the reader actually
/// consumes (`text` / `start_ts` / `end_ts`). Using it downstream lets word timings be persisted to
/// disk (A1) and keeps `SentenceAudio`, `GaplessSentenceScheduler`, and `AudioDiskCache` free of any
/// Kokoro/MLX dependency. `MToken` is mapped to `WordTiming` once, at the generation boundary.
nonisolated struct WordTiming: Codable, Equatable {
    let text: String
    let start: Double?
    let end: Double?
}
