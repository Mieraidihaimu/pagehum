import CryptoKit
import Foundation

/// Finds the Kokoro model: bundled with the app (Debug builds), or downloaded once to Application Support.
nonisolated struct ModelStore: Sendable {
    struct Asset: Sendable {
        let name: String
        let sha256: String
        let url: URL
        let size: Int64
    }

    enum DownloadError: LocalizedError {
        case checksumMismatch(String)
        case unavailable
        var errorDescription: String? {
            switch self {
            case .checksumMismatch(let name): "\(name) didn’t download correctly. Please try again."
            case .unavailable: "Couldn’t download the voice model. Check your connection and try again."
            }
        }
    }

    // Same pinned revision and checksums as scripts/download-models.sh.
    static let standardAssets: [Asset] = [
        Asset(name: "kokoro-v1_0.safetensors",
              sha256: "4e9ecdf03b8b6cf906070390237feda473dc13327cb8d56a43deaa374c02acd8",
              url: URL(string: "https://media.githubusercontent.com/media/mlalma/KokoroTestApp/9dcd3b06468a3c1ecee6d09a33ca687c8e708566/Resources/kokoro-v1_0.safetensors")!,
              size: 327_115_152),
        Asset(name: "voices.npz",
              sha256: "56dbfa2f2970af2e395397020393d368c5f441d09b3de4e9b77f6222e790f10f",
              url: URL(string: "https://raw.githubusercontent.com/mlalma/KokoroTestApp/9dcd3b06468a3c1ecee6d09a33ca687c8e708566/Resources/voices.npz")!,
              size: 14_629_684),
    ]

    static let standard = ModelStore(
        assets: standardAssets,
        bundleDirectory: Bundle.main.resourceURL,
        downloadDirectory: URL.applicationSupportDirectory.appending(path: "KokoroModel", directoryHint: .isDirectory)
    )

    let assets: [Asset]
    let bundleDirectory: URL?
    let downloadDirectory: URL

    var downloadSize: Int64 { assets.reduce(0) { $0 + $1.size } }

    /// The first directory holding every asset. Downloads land there only after verification.
    func modelDirectory() -> URL? {
        [bundleDirectory, downloadDirectory].compactMap { $0 }.first { directory in
            assets.allSatisfy { FileManager.default.fileExists(atPath: directory.appending(path: $0.name).path) }
        }
    }

    /// Downloads missing assets, verifying each checksum before it becomes visible to `modelDirectory()`.
    func download(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        var directory = downloadDirectory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)

        let total = Double(max(downloadSize, 1))
        var completed: Int64 = 0
        for asset in assets {
            let destination = downloadDirectory.appending(path: asset.name)
            if !fileManager.fileExists(atPath: destination.path) {
                let partial = downloadDirectory.appending(path: asset.name + ".partial")
                let base = completed
                try await FileDownload(destination: partial) { written in
                    progress(Double(base + written) / total)
                }.run(from: asset.url)
                guard try Self.sha256(of: partial) == asset.sha256 else {
                    try? fileManager.removeItem(at: partial)
                    throw DownloadError.checksumMismatch(asset.name)
                }
                try fileManager.moveItem(at: partial, to: destination)
            }
            completed += asset.size
            progress(Double(completed) / total)
        }
        return downloadDirectory
    }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// One download task with byte progress; the file is moved to `destination` before completion.
nonisolated private final class FileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: @Sendable (Int64) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var failure: Error?
    private var lastReported: Int64 = 0

    init(destination: URL, onProgress: @escaping @Sendable (Int64) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    func run(from url: URL) async throws {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        defer { session.finishTasksAndInvalidate() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock(); self.continuation = continuation; lock.unlock()
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // Report about once per megabyte so the UI isn't flooded.
        guard totalBytesWritten - lastReported >= 1 << 20 else { return }
        lastReported = totalBytesWritten
        onProgress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            failure = ModelStore.DownloadError.unavailable
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            failure = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        if let error = error ?? failure {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
    }
}
