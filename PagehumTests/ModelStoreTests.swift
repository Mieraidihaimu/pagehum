import CryptoKit
import Foundation
import Testing
@testable import Pagehum

struct ModelStoreTests {
    @Test
    func prefersBundledModelThenDownloadedModel() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appending(path: "bundle"), downloads = root.appending(path: "downloads")
        let source = try sourceAssets(in: root)
        let store = ModelStore(assets: source, bundleDirectory: bundle, downloadDirectory: downloads)
        #expect(store.modelDirectory() == nil)
        try copy(source, into: downloads)
        #expect(store.modelDirectory() == downloads)
        try copy(source, into: bundle)
        #expect(store.modelDirectory() == bundle)
    }

    @Test
    func downloadVerifiesChecksumsReportsProgressAndRejectsCorruptFiles() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let downloads = root.appending(path: "downloads")
        let store = ModelStore(assets: try sourceAssets(in: root), bundleDirectory: nil, downloadDirectory: downloads)
        let progress = ProgressLog()
        let directory = try await store.download { progress.record($0) }
        #expect(directory == downloads)
        #expect(store.modelDirectory() == downloads)
        #expect(progress.last == 1)

        let corrupt = ModelStore.Asset(name: "corrupt.bin", sha256: String(repeating: "0", count: 64),
                                       url: root.appending(path: "source/alpha.bin"), size: 5)
        let badStore = ModelStore(assets: [corrupt], bundleDirectory: nil, downloadDirectory: downloads)
        await #expect(throws: ModelStore.DownloadError.self) { try await badStore.download { _ in } }
        #expect(!FileManager.default.fileExists(atPath: downloads.appending(path: "corrupt.bin").path))
        #expect(badStore.modelDirectory() == nil)
    }

    @Test
    func repairsExistingCorruptAssetAndRemovesStagingFiles() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let assets = try sourceAssets(in: root)
        let downloads = root.appending(path: "downloads")
        try copy(assets, into: downloads)
        let damaged = downloads.appending(path: assets[0].name)
        try Data("bad".utf8).write(to: damaged)
        let store = ModelStore(assets: assets, bundleDirectory: nil, downloadDirectory: downloads)
        #expect(store.modelDirectory() == nil)
        _ = try await store.download { _ in }
        #expect(try ModelStore.sha256(of: damaged) == assets[0].sha256)
        #expect(store.modelDirectory() == downloads)
        #expect(try FileManager.default.contentsOfDirectory(atPath: downloads.path).sorted() == assets.map(\.name).sorted())
    }

    @Test
    func cancelledDownloadDoesNotInstallAnAsset() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let downloads = root.appending(path: "downloads")
        let store = ModelStore(assets: try sourceAssets(in: root), bundleDirectory: nil, downloadDirectory: downloads)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.download { _ in }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(store.modelDirectory() == nil)
    }

    @Test
    func pinnedAssetsMatchTheSetupScript() throws {
        #expect(ModelStore.standardAssets.map(\.name) == ["kokoro-v1_0.safetensors", "voices.npz"])
        #expect(ModelStore.standardAssets.allSatisfy { $0.url.scheme == "https" && $0.sha256.count == 64 })
        #expect(ModelStore.standardAssets.reduce(0) { $0 + $1.size } > 300_000_000)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "ModelStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sourceAssets(in root: URL) throws -> [ModelStore.Asset] {
        let source = root.appending(path: "source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        return try [("alpha.bin", "alpha"), ("bravo.bin", "bravo!")].map { name, contents in
            let url = source.appending(path: name)
            try Data(contents.utf8).write(to: url)
            let digest = SHA256.hash(data: Data(contents.utf8)).map { String(format: "%02x", $0) }.joined()
            return ModelStore.Asset(name: name, sha256: digest, url: url, size: Int64(contents.utf8.count))
        }
    }

    private func copy(_ assets: [ModelStore.Asset], into directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for asset in assets { try FileManager.default.copyItem(at: asset.url, to: directory.appending(path: asset.name)) }
    }
}

nonisolated private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func record(_ value: Double) { lock.lock(); values.append(value); lock.unlock() }
    var last: Double? { lock.lock(); defer { lock.unlock() }; return values.last }
}
