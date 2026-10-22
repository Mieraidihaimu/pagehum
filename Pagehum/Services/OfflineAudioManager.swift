import AVFoundation
import Combine
import Foundation

@MainActor
final class OfflineAudioManager: ObservableObject {
    struct Progress {
        enum State { case queued, saving, waitingForForeground, paused, ready, failed }
        var state: State
        var completed: Int
        let total: Int
        let title: String
        var message: String?
        var fraction: Double { Double(completed) / Double(max(1, total)) }
        var label: String {
            switch state {
            case .queued: "Queued for offline audio"
            case .saving: "Saving audio · \(Int(fraction * 100))%"
            case .waitingForForeground: "Open Pagehum to finish saving · \(Int(fraction * 100))%"
            case .paused: "Offline save paused · \(Int(fraction * 100))%"
            case .ready: "Audio saved offline"
            case .failed: message ?? "Audio could not be saved"
            }
        }
    }

    @Published private(set) var progress: [String: Progress] = [:]
    let store: OfflineAudioStore
    private let generate: (String, String) async -> SentenceAudio?
    private let canPrepare: () -> Bool
    private var pending: [String] = []
    private var task: Task<Void, Never>?

    init(store: OfflineAudioStore, canPrepare: @escaping () -> Bool, generate: @escaping (String, String) async -> SentenceAudio?) {
        self.store = store
        self.canPrepare = canPrepare
        self.generate = generate
        for record in store.allRecords() {
            let state: Progress.State = record.isReady ? .ready : record.failure != nil ? .failed : record.userPaused ? .paused : .waitingForForeground
            update(record, state: state, message: record.failure)
            if !record.isReady && !record.userPaused { pending.append(record.request.id) }
        }
    }

    func enqueue(_ requests: [OfflineAudioRequest]) {
        for request in requests where !request.sentences.isEmpty {
            do {
                let record = try store.register(request)
                update(record, state: record.isReady ? .ready : .queued)
                if !record.isReady && !pending.contains(request.id) { pending.append(request.id) }
            } catch {
                progress[request.id] = Progress(state: .failed, completed: 0, total: request.sentences.count, title: request.title, message: error.localizedDescription)
            }
        }
        resume()
    }

    func pause(_ id: String) {
        pending.removeAll { $0 == id }
        store.pause(id)
        if let record = store.record(id) { update(record, state: .paused) }
    }

    func remove(_ id: String) {
        pause(id)
        do {
            try store.remove(id)
            progress[id] = nil
        } catch { if let record = store.record(id) { update(record, state: .failed, message: error.localizedDescription) } }
    }

    func suspend() {
        for id in pending {
            if let record = store.record(id) { update(record, state: .waitingForForeground) }
        }
    }

    func resume() {
        guard task == nil, canPrepare(), !pending.isEmpty else { return }
        task = Task { [weak self] in
            guard let self else { return }
            while self.canPrepare(), let id = self.pending.first, let record = self.store.record(id) {
                let request = record.request
                self.update(record, state: .saving)
                for index in request.sentences.indices {
                    guard self.pending.contains(id), self.canPrepare() else { break }
                    if self.store.load(id: id, index: index) != nil { continue }
                    let audio = await self.generate(request.sentences[index], request.voice)
                    guard self.pending.contains(id) else { break }
                    if let audio {
                        do {
                            let store = self.store
                            let saved = try await withCheckedThrowingContinuation { continuation in
                                DispatchQueue.global(qos: .utility).async {
                                    continuation.resume(with: Result { try store.save(audio, id: id, index: index) })
                                }
                            }
                            if self.pending.contains(id) {
                                self.update(saved, state: saved.isReady ? .ready : self.canPrepare() ? .saving : .waitingForForeground)
                            }
                        } catch { self.fail(id, message: error.localizedDescription); break }
                    } else if self.canPrepare() {
                        self.fail(id, message: "Audio could not be saved. Retry to continue from the saved position.")
                        break
                    } else { break }
                    await Task.yield()
                }
                if self.store.record(id)?.isReady == true { self.pending.removeAll { $0 == id } }
            }
            self.task = nil
            if !self.canPrepare() { self.suspend() }
        }
    }

    private func fail(_ id: String, message: String) {
        pending.removeAll { $0 == id }
        store.pause(id, failure: message)
        if let record = store.record(id) { update(record, state: .failed, message: message) }
    }

    private func update(_ record: OfflineAudioStore.Record, state: Progress.State, message: String? = nil) {
        progress[record.request.id] = Progress(state: state, completed: record.completed.count, total: record.request.sentences.count, title: record.request.title, message: message)
    }
}
