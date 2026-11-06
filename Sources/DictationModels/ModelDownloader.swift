import Foundation

protocol ModelTransport: Sendable {
    /// The caller owns and removes the returned temporary file.
    func fetch(_ url: URL, expectedBytes: Int64,
        progress: @escaping @Sendable (Int64) -> Void) async throws -> URL
}

struct HTTPSModelTransport: ModelTransport {
    func fetch(_ url: URL, expectedBytes: Int64,
        progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
        guard url.scheme == "https" else { throw ModelDownloadError.invalidResponse }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 3_600
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let delegate = DownloadProgress(expectedBytes: expectedBytes, progress: progress)
        var request = URLRequest(url: url)
        request.setValue("FroggyTalkie/0.5", forHTTPHeaderField: "User-Agent")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let (temporary, response) = try await session.download(for: request, delegate: delegate)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.scheme == "https" else {
            try? FileManager.default.removeItem(at: temporary)
            throw ModelDownloadError.invalidResponse
        }
        return temporary
    }
}

private final class DownloadProgress: NSObject, URLSessionDownloadDelegate {
    let expectedBytes: Int64
    let progress: @Sendable (Int64) -> Void
    init(expectedBytes: Int64, progress: @escaping @Sendable (Int64) -> Void) {
        self.expectedBytes = expectedBytes
        self.progress = progress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Hugging Face redirects large files to its CDN. Never allow an HTTP downgrade.
        completionHandler(request.url?.scheme == "https" ? request : nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > expectedBytes { downloadTask.cancel(); return }
        progress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL) {}
}

public actor ModelDownloader {
    private let transport: any ModelTransport
    private var busy = false

    public init() { transport = HTTPSModelTransport() }
    init(transport: any ModelTransport) { self.transport = transport }

    /// Install only a complete verified directory. A failed download leaves the
    /// previous model in place; a repaired installation preserves it as a backup.
    public func install(to root: URL, manifest: ModelManifest,
        progress: @escaping @Sendable (Int64, Int64) -> Void = { _, _ in }) async throws {
        guard !busy else { throw ModelDownloadError.busy }
        busy = true
        defer { busy = false }
        try manifest.validate()
        try Task.checkCancellation()
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        // Parent directories may legitimately be system symlinks (e.g. /var).
        // Resolve the root once, and never traverse symlinks inside the model.
        let root = root.resolvingSymlinksInPath()
        let destination = root.appendingPathComponent(manifest.directory, isDirectory: true)
        try rejectSymlinks(in: destination, files: manifest.files)
        if try isComplete(destination, manifest: manifest) {
            progress(manifest.totalBytes, manifest.totalBytes)
            return
        }
        let staging = root.appendingPathComponent(".\(manifest.directory)-\(UUID().uuidString).partial", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        var completed: Int64 = 0
        do {
            for file in manifest.files {
                try Task.checkCancellation()
                let staged = staging.appendingPathComponent(file.path)
                try fm.createDirectory(at: staged.deletingLastPathComponent(), withIntermediateDirectories: true)
                let existing = destination.appendingPathComponent(file.path)
                if fm.fileExists(atPath: existing.path), try ModelFileVerifier.verify(existing, file: file) {
                    try fm.copyItem(at: existing, to: staged)
                } else {
                    let previous = completed
                    let temporary = try await transport.fetch(manifest.url(for: file), expectedBytes: file.bytes) {
                        progress(previous + min(max(0, $0), file.bytes), manifest.totalBytes)
                    }
                    defer { try? fm.removeItem(at: temporary) }
                    guard try ModelFileVerifier.verify(temporary, file: file) else {
                        throw ModelDownloadError.integrity(file.path)
                    }
                    try fm.moveItem(at: temporary, to: staged)
                }
                completed += file.bytes
                progress(completed, manifest.totalBytes)
            }
            try Task.checkCancellation()
            // Recheck copied files as well, before making this directory visible.
            guard try isComplete(staging, manifest: manifest) else {
                throw ModelDownloadError.integrity(manifest.directory)
            }
            try rejectSymlinks(in: destination, files: manifest.files)
            let backup = root.appendingPathComponent("\(manifest.directory)-previous-\(UUID().uuidString)")
            let hadPrevious = fm.fileExists(atPath: destination.path)
            if hadPrevious { try fm.moveItem(at: destination, to: backup) }
            do { try fm.moveItem(at: staging, to: destination) }
            catch {
                if hadPrevious { try? fm.moveItem(at: backup, to: destination) }
                throw error
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    private func isComplete(_ directory: URL, manifest: ModelManifest) throws -> Bool {
        for file in manifest.files {
            let url = directory.appendingPathComponent(file.path)
            guard FileManager.default.fileExists(atPath: url.path),
                  try ModelFileVerifier.verify(url, file: file) else { return false }
        }
        return true
    }

    private func rejectSymlinks(in directory: URL, files: [ModelManifest.File]) throws {
        for path in [""] + files.map(\.path) {
            var url = directory
            for component in [""] + path.split(separator: "/").map(String.init) {
                if !component.isEmpty { url.appendPathComponent(component) }
                if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                    throw ModelDownloadError.unsafeDirectory
                }
            }
        }
    }
}
