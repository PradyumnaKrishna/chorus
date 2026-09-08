import CryptoKit
import Foundation

public struct StagedArtifact: Sendable {
    public let descriptor: ArtifactDescriptor
    public let fileURL: URL

    public init(descriptor: ArtifactDescriptor, fileURL: URL) {
        self.descriptor = descriptor
        self.fileURL = fileURL
    }
}

/// Owns the verified files installed for one provider.
public struct ArtifactStore: Sendable {
    public let rootDirectory: URL
    public let artifacts: [ArtifactDescriptor]

    public init(rootDirectory: URL, artifacts: [ArtifactDescriptor]) {
        self.rootDirectory = rootDirectory
        self.artifacts = artifacts
    }

    public enum Presence: Sendable, Equatable {
        case absent
        /// Files are present but declared by an earlier manifest than this one.
        case outdated
        case installed
    }

    /// What is on disk, compared against the manifest.
    ///
    /// Sizes rather than checksums: digesting an installed model on a launch path
    /// would be far too slow, and it was verified when the file was written.
    public func presence(fileManager: FileManager = .default) -> Presence {
        var present = false
        var matching = true
        for artifact in artifacts {
            let values = try? destination(for: artifact).resourceValues(forKeys: [.fileSizeKey])
            guard let size = values?.fileSize else { matching = false; continue }
            present = true
            matching = matching && Int64(size) == artifact.expectedByteCount
        }
        if matching { return .installed }
        return present ? .outdated : .absent
    }

    public func isInstalled(fileManager: FileManager = .default) -> Bool {
        presence(fileManager: fileManager) == .installed
    }

    /// Verifies every staged artifact before replacing any installed file.
    ///
    /// Existing files are backed up during the commit and restored if a file-system operation fails.
    ///
    /// @param stagedArtifacts One downloaded file for every configured artifact.
    /// @throws ``StoreError`` for an incomplete or invalid payload, or a file-system error.
    public func install(
        _ stagedArtifacts: [StagedArtifact],
        fileManager: FileManager = .default
    ) throws {
        let stagedByIdentifier = Dictionary(
            uniqueKeysWithValues: stagedArtifacts.map { ($0.descriptor.identifier, $0) }
        )
        guard stagedByIdentifier.count == artifacts.count,
              artifacts.allSatisfy({ stagedByIdentifier[$0.identifier] != nil }) else {
            throw StoreError.incompletePayload
        }

        for artifact in artifacts {
            guard let staged = stagedByIdentifier[artifact.identifier] else {
                throw StoreError.incompletePayload
            }
            try verify(staged.fileURL, against: artifact)
        }

        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let transactionDirectory = rootDirectory
            .appendingPathComponent(".transaction-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: transactionDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: transactionDirectory) }

        var commits: [(destination: URL, backup: URL?)] = []
        do {
            for (index, artifact) in artifacts.enumerated() {
                guard let staged = stagedByIdentifier[artifact.identifier] else {
                    throw StoreError.incompletePayload
                }
                let pending = transactionDirectory.appendingPathComponent("pending-\(index)")
                try fileManager.moveItem(at: staged.fileURL, to: pending)

                let destination = destination(for: artifact)
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                var backup: URL?
                if fileManager.fileExists(atPath: destination.path) {
                    let backupURL = transactionDirectory.appendingPathComponent("backup-\(index)")
                    try fileManager.moveItem(at: destination, to: backupURL)
                    backup = backupURL
                }
                commits.append((destination, backup))
                try fileManager.moveItem(at: pending, to: destination)
            }
        } catch {
            for commit in commits.reversed() {
                if fileManager.fileExists(atPath: commit.destination.path) {
                    try? fileManager.removeItem(at: commit.destination)
                }
                if let backup = commit.backup, fileManager.fileExists(atPath: backup.path) {
                    try? fileManager.moveItem(at: backup, to: commit.destination)
                }
            }
            throw error
        }
    }

    /// Removes only files declared by this provider.
    public func uninstall(fileManager: FileManager = .default) throws {
        for artifact in artifacts {
            let url = destination(for: artifact)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
        guard !isInstalled(fileManager: fileManager) else { throw StoreError.artifactsRemain }
    }

    public func destination(for artifact: ArtifactDescriptor) -> URL {
        rootDirectory.appendingPathComponent(artifact.relativePath)
    }

    private func verify(_ url: URL, against artifact: ArtifactDescriptor) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard Int64(values.fileSize ?? -1) == artifact.expectedByteCount else {
            throw StoreError.invalidSize(artifact.identifier)
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            digest.update(data: data)
        }
        let checksum = digest.finalize().map { String(format: "%02x", $0) }.joined()
        guard checksum == artifact.sha256 else {
            throw StoreError.invalidChecksum(artifact.identifier)
        }
    }

    public enum StoreError: LocalizedError {
        case incompletePayload
        case invalidSize(String)
        case invalidChecksum(String)
        case artifactsRemain

        public var errorDescription: String? {
            switch self {
            case .incompletePayload:
                return "The download did not contain every required artifact."
            case .invalidSize(let identifier):
                return "The artifact ‘\(identifier)’ has an unexpected size."
            case .invalidChecksum(let identifier):
                return "The artifact ‘\(identifier)’ failed verification. Your installation was not changed."
            case .artifactsRemain:
                return "Some provider artifacts could not be removed."
            }
        }
    }
}
