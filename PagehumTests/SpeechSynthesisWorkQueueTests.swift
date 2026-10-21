import Foundation
import Testing
@testable import Pagehum

struct SpeechSynthesisWorkQueueTests {
    @Test
    func suspensionWaitsForInferenceAndRejectsWorkUntilResumed() async throws {
        let queue = SpeechSynthesisWorkQueue()
        let events = SynthesisEvents()
        let release = DispatchSemaphore(value: 0)
        let inference = Task {
            try await queue.perform {
                events.append("started")
                guard release.wait(timeout: .now() + 5) == .success else { return false }
                events.append("finished")
                return true
            }
        }
        let deadline = Date().addingTimeInterval(5)
        while events.values.isEmpty && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(events.values == ["started"])

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { release.signal() }
        queue.suspendAndDrain { events.append("drained") }
        #expect(try await inference.value)
        #expect(events.values == ["started", "finished", "drained"])

        await #expect(throws: SpeechSynthesisWorkQueue.WorkError.self) {
            try await queue.perform { events.append("unexpected") }
        }
        #expect(events.values == ["started", "finished", "drained"])
        queue.resume()
        try await queue.perform { events.append("resumed") }
        #expect(events.values.last == "resumed")
    }

    @Test
    func suspensionWithoutKokoroWorkDoesNotInitializeGPUCleanup() async {
        let queue = SpeechSynthesisWorkQueue()
        let events = SynthesisEvents()
        queue.suspendAndDrain { events.append("unexpected GPU cleanup") }
        #expect(events.values.isEmpty)
        await #expect(throws: SpeechSynthesisWorkQueue.WorkError.self) {
            try await queue.perform { events.append("unexpected inference") }
        }
    }
}

nonisolated private final class SynthesisEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func append(_ event: String) {
        lock.lock(); defer { lock.unlock() }
        storage.append(event)
    }
}
