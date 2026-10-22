import AVFoundation
import CryptoKit
import Foundation

nonisolated struct OfflineAudioRequest: Codable {
    let id: String
    let textID: String
    let title: String
    let voice: String
    let sentences: [String]
    let offsets: [Int]
    let codeBlocks: [Int: CodeBlock]

    static func textIdentifier(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func identifier(textID: String, voice: String) -> String {
        textIdentifier("offline-v1|\(voice)|\(textID)")
    }

    init(text: String, title: String, voice: String, sentences: [String], offsets: [Int], codeBlocks: [Int: CodeBlock]) {
        textID = Self.textIdentifier(text)
        id = Self.identifier(textID: textID, voice: voice)
        self.title = title
        self.voice = voice
        self.sentences = sentences
        self.offsets = offsets
        self.codeBlocks = codeBlocks
    }
}

/// Explicitly saved audio has its own directory and is never evicted by the playback cache.
/// Each sentence is committed before its checkpoint, so interrupted saves can resume safely.
nonisolated final class OfflineAudioStore: @unchecked Sendable {
    struct Record: Codable {
        let request: OfflineAudioRequest
        var completed: Set<Int> = []
        var userPaused = false
        var failure: String?
        var isReady: Bool { !request.sentences.isEmpty && completed.count == request.sentences.count }
    }

    static let standard = OfflineAudioStore(directory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("OfflineAudio", isDirectory: true))
    private let directory: URL
    private let queue = DispatchQueue(label: "com.pagehum.offline-audio")
    private var records: [String: Record] = [:]
    private var caches: [String: AudioDiskCache] = [:]

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        for folder in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
                  var record = try? JSONDecoder().decode(Record.self, from: data),
                  record.request.id == folder.lastPathComponent else { continue }
            let cache = AudioDiskCache(maxBytes: .max, directory: folder.appendingPathComponent("Audio"))
            record.completed = record.completed.filter {
                record.request.sentences.indices.contains($0) && cache.contains(text: record.request.sentences[$0], voiceKey: record.request.voice + ".npy")
            }
            records[record.request.id] = record
            caches[record.request.id] = cache
        }
    }

    func allRecords() -> [Record] { queue.sync { Array(records.values) } }
    func record(_ id: String) -> Record? { queue.sync { records[id] } }

    func readyRequest(textID: String, preferredVoice: String) -> OfflineAudioRequest? {
        queue.sync {
            let matches = records.values.filter { $0.request.textID == textID && $0.isReady }
            return (matches.first { $0.request.voice == preferredVoice } ?? matches.sorted { $0.request.id < $1.request.id }.first)?.request
        }
    }

    @discardableResult
    func register(_ request: OfflineAudioRequest) throws -> Record {
        try queue.sync {
            var record = records[request.id] ?? Record(request: request)
            record.userPaused = false
            record.failure = nil
            records[request.id] = record
            try persist(record)
            return record
        }
    }

    func load(id: String, index: Int) -> SentenceAudio? {
        queue.sync {
            guard let record = records[id], record.request.sentences.indices.contains(index), record.completed.contains(index) else { return nil }
            return cache(for: id).load(text: record.request.sentences[index], voiceKey: record.request.voice + ".npy")
        }
    }

    func save(_ audio: SentenceAudio, id: String, index: Int) throws -> Record {
        try queue.sync {
            guard var record = records[id], record.request.sentences.indices.contains(index) else { throw CocoaError(.fileNoSuchFile) }
            let cache = cache(for: id)
            let text = record.request.sentences[index]
            cache.store(text: text, voiceKey: record.request.voice + ".npy", buffer: audio.buffer, tokens: audio.tokens)
            // Loading drains the cache's serial writer and verifies a usable committed clip.
            guard cache.load(text: text, voiceKey: record.request.voice + ".npy") != nil else { throw CocoaError(.fileWriteUnknown) }
            record.completed.insert(index)
            records[id] = record
            try persist(record)
            return record
        }
    }

    func pause(_ id: String, failure: String? = nil) {
        queue.sync {
            guard var record = records[id] else { return }
            record.userPaused = true
            record.failure = failure
            records[id] = record
            try? persist(record)
        }
    }

    func remove(_ id: String) throws {
        try queue.sync {
            let folder = directory.appendingPathComponent(id)
            if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
            records[id] = nil
            caches[id] = nil
        }
    }

    private func cache(for id: String) -> AudioDiskCache {
        if let cache = caches[id] { return cache }
        let cache = AudioDiskCache(maxBytes: .max, directory: directory.appendingPathComponent(id).appendingPathComponent("Audio"))
        caches[id] = cache
        return cache
    }

    private func persist(_ record: Record) throws {
        let folder = directory.appendingPathComponent(record.request.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: folder.path)
        #endif
        try JSONEncoder().encode(record).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
    }
}
