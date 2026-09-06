import Foundation

/// Downloads one declared artifact to a staging file.
///
/// This bridges `URLSession`'s delegate API to async/await rather than calling
/// `URLSession.download(from:)` directly, because the async download API does
/// not deliver `urlSession(_:downloadTask:didWriteData:…)` to a per-task *or* a
/// session delegate -- verified, not assumed -- and a multi-megabyte model needs
/// a progress bar. Bridging keeps cancellation structural: cancelling the
/// enclosing task tears the transfer down.
public enum ArtifactDownloader {

    /// Downloads `artifact` into `directory` under a unique name.
    ///
    /// The returned file is unverified; `ArtifactStore.install(_:)` checks size
    /// and digest before anything is committed. The caller owns the staged file
    /// and must remove it if the install does not proceed.
    ///
    /// @param onProgress Total bytes written so far, called on a session queue.
    /// @return The staged artifact, ready to hand to `ArtifactStore`.
    public static func download(
        _ artifact: ArtifactDescriptor,
        into directory: URL,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws -> StagedArtifact {
        let destination = directory
            .appendingPathComponent("chorus-download-\(UUID().uuidString)")
        let delegate = Delegate(destination: destination, onProgress: onProgress)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 30
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)

        let fileURL = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.attach(continuation)
                session.downloadTask(with: artifact.source).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
        session.finishTasksAndInvalidate()
        return StagedArtifact(descriptor: artifact, fileURL: fileURL)
    }

    /// Resumes its continuation exactly once, from whichever callback lands first.
    private final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        private let destination: URL
        private let onProgress: @Sendable (Int64) -> Void
        private let lock = NSLock()
        private var continuation: CheckedContinuation<URL, Error>?

        init(destination: URL, onProgress: @escaping @Sendable (Int64) -> Void) {
            self.destination = destination
            self.onProgress = onProgress
        }

        func attach(_ continuation: CheckedContinuation<URL, Error>) {
            lock.lock()
            defer { lock.unlock() }
            self.continuation = continuation
        }

        private func finish(_ result: Result<URL, Error>) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(with: result)
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            onProgress(totalBytesWritten)
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didFinishDownloadingTo location: URL
        ) {
            if let response = downloadTask.response as? HTTPURLResponse,
               !(200...299).contains(response.statusCode) {
                finish(.failure(ArtifactDownloadError.serverResponse(response.statusCode)))
                return
            }
            // URLSession removes `location` as soon as this returns, so claim it here.
            do {
                try FileManager.default.moveItem(at: location, to: destination)
                finish(.success(destination))
            } catch {
                finish(.failure(error))
            }
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didCompleteWithError error: Error?
        ) {
            guard let error else { return }
            finish(.failure(error))
        }
    }
}

public enum ArtifactDownloadError: LocalizedError {
    case serverResponse(Int)

    public var errorDescription: String? {
        switch self {
        case .serverResponse(let statusCode):
            return "The download server returned HTTP \(statusCode). Please try again."
        }
    }
}
