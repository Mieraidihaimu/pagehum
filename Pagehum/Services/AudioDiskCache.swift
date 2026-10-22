// Modified for Pagehum: unified application and command-line naming.
import AVFoundation
import CryptoKit
import Foundation

/// Persists generated sentence audio (AAC `.m4a`) plus word timings (JSON sidecar) to disk so
/// re-reads, seeks, and offline playback skip Kokoro inference. See `docs/A1_DISK_CACHE_DESIGN.md`.
///
/// **Design contract:** the cache is a pure *optimization*. `load` returns `nil` on ANY imperfection
/// (missing / corrupt / format-mismatch / decode error / schema bump) so the caller regenerates — it
/// must never crash. All file I/O is confined to one serial queue; callers invoke it from a
/// background thread (never the main thread). No `try!`, no force-unwraps on the read path.
///
/// Deliberately free of any Kokoro/MLX dependency (deals only in `AVAudioPCMBuffer` + `WordTiming`),
/// so it is unit-testable off-device.
nonisolated final class AudioDiskCache: @unchecked Sendable {

    static let shared = AudioDiskCache()

    /// Bump to invalidate every previously-cached entry after a format/pipeline change.
    private static let schemaVersion = 1
    private static let modelTag = "kokoro-v1_0"
    private static let sampleRate: Double = 24_000
    private static let aacBitRate = 32_000
    /// Standard AAC-LC encoder priming; used to trim/compensate decoded cache hits.
    private static let aacPrimingFrames: AVAudioFrameCount = 2112

    private let maxBytes: Int64
    private let injectedDirectory: URL?
    private let queue = DispatchQueue(label: "com.pagehum.audiodiskcache")

    /// - Parameters:
    ///   - maxBytes: LRU budget for the cache directory.
    ///   - directory: override the on-disk location (unit tests pass a temp dir); `nil` uses the
    ///     shared `Documents/AudioCache`.
    init(maxBytes: Int64 = 500 * 1024 * 1024, directory: URL? = nil) {
        self.maxBytes = maxBytes
        self.injectedDirectory = directory
    }

    private var directory: URL {
        guard let injectedDirectory else { return AudioCacheManager.cacheDirectory }
        try? FileManager.default.createDirectory(at: injectedDirectory, withIntermediateDirectories: true)
        return injectedDirectory
    }

    // MARK: - Metadata sidecar

    private struct Metadata: Codable {
        let schemaVersion: Int
        let sampleRate: Double
        let originalFrameLength: Int64
        let tokens: [WordTiming]?
    }

    // MARK: - Key

    private func fileBase(text: String, voiceKey: String) -> String {
        let material = "\(Self.schemaVersion)|\(Self.modelTag)|\(voiceKey)|\(text)"
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Load

    func contains(text: String, voiceKey: String) -> Bool {
        queue.sync {
            let base = fileBase(text: text, voiceKey: voiceKey)
            return ["m4a", "json"].allSatisfy {
                FileManager.default.fileExists(atPath: directory.appendingPathComponent(base + "." + $0).path)
            }
        }
    }

    /// Returns cached audio for `text`+`voiceKey`, or `nil` (a miss) on any problem.
    func load(text: String, voiceKey: String) -> SentenceAudio? {
        queue.sync {
            let base = fileBase(text: text, voiceKey: voiceKey)
            let audioURL = directory.appendingPathComponent(base + ".m4a")
            let metaURL = directory.appendingPathComponent(base + ".json")
            let fm = FileManager.default

            // `.json` is the commit marker — both must exist.
            guard fm.fileExists(atPath: audioURL.path), fm.fileExists(atPath: metaURL.path) else {
                return nil
            }

            // Metadata (schema-gated).
            guard let metaData = try? Data(contentsOf: metaURL),
                  let meta = try? JSONDecoder().decode(Metadata.self, from: metaData),
                  meta.schemaVersion == Self.schemaVersion else {
                return nil
            }

            // Audio → forced to Float32 non-interleaved so processingFormat is predictable.
            guard let file = try? AVAudioFile(forReading: audioURL,
                                              commonFormat: .pcmFormatFloat32,
                                              interleaved: false) else {
                return nil
            }
            let fmt = file.processingFormat
            guard fmt.sampleRate == Self.sampleRate, fmt.channelCount == 1, file.length > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: fmt,
                                                frameCapacity: AVAudioFrameCount(file.length)) else {
                return nil
            }
            do { try file.read(into: buffer) } catch { return nil }
            guard buffer.frameLength > 0 else { return nil }

            // Undo AAC priming so cached audio stays gapless + highlight-aligned.
            let original = AVAudioFrameCount(max(0, meta.originalFrameLength))
            let (finalBuffer, leading) = Self.compensatePriming(buffer, originalFrames: original)

            // Touch mtime for LRU.
            try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: audioURL.path)

            return SentenceAudio(buffer: finalBuffer, tokens: meta.tokens, leadingSilence: leading)
        }
    }

    /// If the decoded buffer is longer than the original PCM, the head is AAC priming. Prefer trimming
    /// it (keeps playback gapless); if trimming can't be done safely, fall back to compensating the
    /// word-highlight clock instead. Never fails.
    private static func compensatePriming(_ decoded: AVAudioPCMBuffer,
                                          originalFrames: AVAudioFrameCount) -> (AVAudioPCMBuffer, TimeInterval) {
        let decodedLen = decoded.frameLength
        guard originalFrames > 0, decodedLen > originalFrames else { return (decoded, 0) }

        let priming = min(aacPrimingFrames, decodedLen - originalFrames)
        let outLen = min(originalFrames, decodedLen - priming)

        if outLen > 0,
           let src = decoded.floatChannelData,
           let out = AVAudioPCMBuffer(pcmFormat: decoded.format, frameCapacity: outLen),
           let dst = out.floatChannelData {
            let channels = Int(decoded.format.channelCount)
            for ch in 0..<channels {
                memcpy(dst[ch], src[ch] + Int(priming), Int(outLen) * MemoryLayout<Float>.size)
            }
            out.frameLength = outLen
            return (out, 0)
        }

        // Trim not possible — shift the highlight clock instead (no audio edit).
        return (decoded, Double(priming) / sampleRate)
    }

    // MARK: - Store

    /// Persist `buffer`+`tokens` for `text`+`voiceKey`. Fire-and-forget; never blocks the caller and
    /// never crashes — any failure just leaves the sentence uncached.
    func store(text: String, voiceKey: String, buffer: AVAudioPCMBuffer, tokens: [WordTiming]?) {
        let originalFrameLength = Int64(buffer.frameLength)
        queue.async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            let base = self.fileBase(text: text, voiceKey: voiceKey)
            let audioURL = self.directory.appendingPathComponent(base + ".m4a")
            let metaURL = self.directory.appendingPathComponent(base + ".json")
            let audioTmp = audioURL.appendingPathExtension("tmp")
            let metaTmp = metaURL.appendingPathExtension("tmp")

            try? fm.removeItem(at: audioTmp)
            try? fm.removeItem(at: metaTmp)

            // 1. Encode AAC audio to a temp file.
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: Self.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: Self.aacBitRate,
            ]
            do {
                let file = try AVAudioFile(forWriting: audioTmp, settings: settings)
                try file.write(from: buffer)
            } catch {
                print("AudioDiskCache: audio write failed — \(error)")
                try? fm.removeItem(at: audioTmp)
                return
            }

            // 2. Write metadata to a temp file.
            let meta = Metadata(schemaVersion: Self.schemaVersion,
                                sampleRate: Self.sampleRate,
                                originalFrameLength: originalFrameLength,
                                tokens: tokens)
            do {
                let data = try JSONEncoder().encode(meta)
                try data.write(to: metaTmp, options: .atomic)
            } catch {
                print("AudioDiskCache: metadata write failed — \(error)")
                try? fm.removeItem(at: audioTmp)
                try? fm.removeItem(at: metaTmp)
                return
            }

            // 3. Commit atomically: audio first, then json last as the commit marker.
            do {
                if fm.fileExists(atPath: audioURL.path) { try? fm.removeItem(at: audioURL) }
                try fm.moveItem(at: audioTmp, to: audioURL)
                if fm.fileExists(atPath: metaURL.path) { try? fm.removeItem(at: metaURL) }
                try fm.moveItem(at: metaTmp, to: metaURL)
            } catch {
                print("AudioDiskCache: commit failed — \(error)")
                try? fm.removeItem(at: audioTmp)
                try? fm.removeItem(at: metaTmp)
                return
            }

            self.enforceBudget()
        }
    }

    // MARK: - LRU eviction

    /// Delete oldest entries (by mtime) until total cache size is under budget. Runs on `queue`.
    private func enforceBudget() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var total: Int64 = 0
        var entries: [(base: String, size: Int64, date: Date)] = []
        for url in urls where url.pathExtension == "m4a" {
            let vals = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let audioSize = Int64(vals?.fileSize ?? 0)
            let date = vals?.contentModificationDate ?? .distantPast
            let metaURL = url.deletingPathExtension().appendingPathExtension("json")
            let metaSize = Int64((try? metaURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            let size = audioSize + metaSize
            total += size
            entries.append((url.deletingPathExtension().lastPathComponent, size, date))
        }

        guard total > maxBytes else { return }
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            if total <= maxBytes { break }
            try? fm.removeItem(at: directory.appendingPathComponent(entry.base + ".m4a"))
            try? fm.removeItem(at: directory.appendingPathComponent(entry.base + ".json"))
            total -= entry.size
        }
    }
}
