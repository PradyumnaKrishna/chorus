import ChorusProviderKit
import Foundation

@MainActor
public final class InstallerController: ObservableObject {
    public enum InstallationStatus: Equatable, Sendable {
        case notInstalled
        case installed
    }

    public enum Operation: Equatable, Sendable {
        case install
        case repair
        case uninstall
    }

    public enum Phase: Equatable, Sendable {
        case ready(InstallationStatus)
        case downloading(Operation, Double)
        case verifying(Operation)
        case removing
        case completed(Operation)
        case failed(Operation, String)
    }

    @Published public private(set) var phase: Phase
    public var onInstallationChanged: (() -> Void)?

    public let descriptor: ProviderDescriptor
    private let store: ArtifactStore?
    private var activeTask: Task<Void, Never>?

    public init(
        descriptor: ProviderDescriptor,
        initialStatus: InstallationStatus? = nil,
        store: ArtifactStore? = nil
    ) {
        self.descriptor = descriptor
        let resolvedStore = store ?? (try? ProviderContainer.storageDirectory()).map {
            ArtifactStore(rootDirectory: $0, artifacts: descriptor.artifacts)
        }
        self.store = resolvedStore
        phase = .ready(initialStatus ?? (resolvedStore?.isInstalled() == true ? .installed : .notInstalled))
    }

    /// Starts an operation only when it is valid for the current installation state.
    public func perform(_ operation: Operation) {
        guard let store else {
            phase = .failed(
                operation,
                ProviderDescriptor.DescriptorError.appGroupUnavailable.localizedDescription
            )
            return
        }
        let isInstalled = store.isInstalled()
        guard (operation == .install && !isInstalled) ||
              (operation != .install && isInstalled) else {
            phase = .ready(isInstalled ? .installed : .notInstalled)
            return
        }

        activeTask?.cancel()
        activeTask = Task { [weak self] in
            await self?.run(operation, store: store)
        }
    }

    public func cancel() {
        activeTask?.cancel()
    }

    private func run(_ operation: Operation, store: ArtifactStore) async {
        do {
            switch operation {
            case .install, .repair:
                try await installArtifacts(for: operation, store: store)
            case .uninstall:
                phase = .removing
                try await Task.detached(priority: .userInitiated) { try store.uninstall() }.value
            }
            phase = .completed(operation)
            onInstallationChanged?()
        } catch {
            // A cancelled URLSession transfer surfaces as NSURLErrorCancelled rather
            // than CancellationError, so neither alone is enough to spot a cancel.
            phase = Self.wasCancelled(error)
                ? .ready(store.isInstalled() ? .installed : .notInstalled)
                : .failed(operation, error.localizedDescription)
        }
        activeTask = nil
    }

    private func installArtifacts(for operation: Operation, store: ArtifactStore) async throws {
        phase = .downloading(operation, 0)

        var staged: [StagedArtifact] = []
        // Every exit that is not a completed install must leave nothing behind: a
        // staged artifact is a full-size copy on disk. Cleaning up here covers the
        // failure, cancellation, and thrown-mid-loop cases in one place.
        defer {
            for artifact in staged {
                try? FileManager.default.removeItem(at: artifact.fileURL)
            }
        }

        let total = max(1, descriptor.expectedByteCount)
        let directory = FileManager.default.temporaryDirectory
        var completed: Int64 = 0

        for artifact in descriptor.artifacts {
            try Task.checkCancellation()
            // Snapshot the running total so the progress closure captures a value
            // rather than sharing a variable across the session's queue.
            let base = completed
            let downloaded = try await ArtifactDownloader.download(artifact, into: directory) { written in
                Task { @MainActor [weak self] in
                    guard let self, case .downloading = self.phase else { return }
                    let bytes = base + min(written, artifact.expectedByteCount)
                    self.phase = .downloading(operation, min(1, max(0, Double(bytes) / Double(total))))
                }
            }
            staged.append(downloaded)
            completed += artifact.expectedByteCount
        }

        try Task.checkCancellation()
        phase = .verifying(operation)

        let payload = staged
        try await Task.detached(priority: .userInitiated) { try store.install(payload) }.value
        guard store.isInstalled() else { throw InstallerError.installationIncomplete }

        // install(_:) consumed the staged files; there is nothing left to remove.
        staged = []
    }

    private static func wasCancelled(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let error = error as NSError
        return error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
    }

    private enum InstallerError: LocalizedError {
        case installationIncomplete

        var errorDescription: String? {
            "The provider artifacts could not be installed. Please try again."
        }
    }
}
