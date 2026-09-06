import Foundation

public struct ProviderDescriptor: Codable, Equatable, Sendable {
    public let identifier: String
    public let displayName: String
    public let summary: String
    public let iconName: String
    public let backgroundColor: String
    public let accentColor: String
    public let artifacts: [ArtifactDescriptor]

    public init(
        identifier: String,
        displayName: String,
        summary: String,
        iconName: String,
        backgroundColor: String,
        accentColor: String,
        artifacts: [ArtifactDescriptor]
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.summary = summary
        self.iconName = iconName
        self.backgroundColor = backgroundColor
        self.accentColor = accentColor
        self.artifacts = artifacts
    }

    /// Loads and validates a provider manifest embedded in a containing app.
    ///
    /// @param bundle Bundle containing `Provider.json`.
    /// @return A descriptor whose URLs, checksums, sizes, and relative paths are valid.
    /// @throws ``DescriptorError`` for missing or malformed configuration.
    public static func load(from bundle: Bundle = .main) throws -> ProviderDescriptor {
        guard let url = bundle.url(forResource: "Provider", withExtension: "json") else {
            throw DescriptorError.missingManifest
        }
        return try load(from: url)
    }

    /// Loads and validates a provider manifest at an explicit file URL.
    public static func load(from url: URL) throws -> ProviderDescriptor {
        let descriptor = try JSONDecoder().decode(ProviderDescriptor.self, from: Data(contentsOf: url))
        try descriptor.validate()
        return descriptor
    }

    public var expectedByteCount: Int64 {
        artifacts.reduce(0) { $0 + $1.expectedByteCount }
    }

    private func validate() throws {
        guard !identifier.isEmpty, !displayName.isEmpty else {
            throw DescriptorError.invalidIdentity
        }
        guard !artifacts.isEmpty else { throw DescriptorError.noArtifacts }

        var identifiers = Set<String>()
        for artifact in artifacts {
            guard identifiers.insert(artifact.identifier).inserted else {
                throw DescriptorError.duplicateArtifact(artifact.identifier)
            }
            try artifact.validate()
        }
    }

    public enum DescriptorError: LocalizedError {
        case missingManifest
        case invalidIdentity
        case noArtifacts
        case duplicateArtifact(String)
        case invalidArtifact(String)
        case appGroupUnavailable

        public var errorDescription: String? {
            switch self {
            case .missingManifest:
                return "The provider manifest is missing from this application."
            case .invalidIdentity:
                return "The provider manifest has an invalid identity."
            case .noArtifacts:
                return "The provider manifest does not contain any installable artifacts."
            case .duplicateArtifact(let identifier):
                return "The provider manifest repeats the artifact ‘\(identifier)’."
            case .invalidArtifact(let identifier):
                return "The artifact ‘\(identifier)’ has invalid download metadata."
            case .appGroupUnavailable:
                return "The provider cannot access its shared container. Check its signing and App Group configuration."
            }
        }
    }
}

public struct ArtifactDescriptor: Codable, Equatable, Sendable {
    public let identifier: String
    public let source: URL
    public let relativePath: String
    public let expectedByteCount: Int64
    public let sha256: String

    public init(
        identifier: String,
        source: URL,
        relativePath: String,
        expectedByteCount: Int64,
        sha256: String
    ) {
        self.identifier = identifier
        self.source = source
        self.relativePath = relativePath
        self.expectedByteCount = expectedByteCount
        self.sha256 = sha256
    }

    fileprivate func validate() throws {
        let path = NSString(string: relativePath).standardizingPath
        let checksumCharacters = CharacterSet(charactersIn: "0123456789abcdef")
        guard !identifier.isEmpty,
              source.scheme == "https",
              !path.isEmpty,
              !path.hasPrefix("/"),
              path != ".",
              path != "..",
              !path.hasPrefix("../"),
              expectedByteCount > 0,
              sha256.count == 64,
              sha256.unicodeScalars.allSatisfy(checksumCharacters.contains) else {
            throw ProviderDescriptor.DescriptorError.invalidArtifact(identifier)
        }
    }
}
