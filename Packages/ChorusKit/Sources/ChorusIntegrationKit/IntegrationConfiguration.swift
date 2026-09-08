import Foundation

/// Manages the user-level lifecycle hook for one supported coding assistant.
///
/// Existing settings and unrelated hooks are preserved. Installation replaces
/// a stale Chorus command when the application has moved.
public struct IntegrationConfiguration {
    public let source: Harness
    public let executable: URL
    public let file: URL

    public init(source: Harness, executable: URL, homeDirectory: URL? = nil,
                environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.source = source
        self.executable = executable
        if let homeDirectory {
            file = homeDirectory
                .appendingPathComponent(source == .codex ? ".codex/hooks.json" : ".claude/settings.json")
        } else if source == .codex, let root = environment["CODEX_HOME"], !root.isEmpty {
            file = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent("hooks.json")
        } else if source == .claude, let root = environment["CLAUDE_CONFIG_DIR"], !root.isEmpty {
            file = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent("settings.json")
        } else {
            file = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(source == .codex ? ".codex/hooks.json" : ".claude/settings.json")
        }
    }

    public var snippet: String { Self.formattedJSON(hookDocument) }

    public func isInstalled() throws -> Bool {
        guard FileManager.default.fileExists(atPath: file.path) else { return false }
        return try stopGroups(in: load()).contains { group in
            commands(in: group).contains(where: isCurrentChorusCommand)
        }
    }

    public func install() throws {
        var document = try load()
        var hooks = try hooksObject(in: document)
        var groups = try stopGroups(in: document)
        groups = removingChorusCommands(from: groups)
        groups.append(hookGroup)
        hooks["Stop"] = groups
        document["hooks"] = hooks
        try write(document)
    }

    private var command: String {
        "'" + executable.path.replacingOccurrences(of: "'", with: "'\\''") + "' " + source.rawValue
    }

    private var commandHook: [String: Any] {
        ["type": "command", "command": command, "async": true, "timeout": 10]
    }

    private var hookGroup: [String: Any] { ["hooks": [commandHook]] }
    private var hookDocument: [String: Any] { ["hooks": ["Stop": [hookGroup]]] }

    private func load() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        guard data.count <= 1_048_576,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigurationError.invalidJSON(file)
        }
        return object
    }

    private func hooksObject(in document: [String: Any]) throws -> [String: Any] {
        guard let value = document["hooks"] else { return [:] }
        guard let hooks = value as? [String: Any] else { throw ConfigurationError.invalidHooks(file) }
        return hooks
    }

    private func stopGroups(in document: [String: Any]) throws -> [[String: Any]] {
        let hooks = try hooksObject(in: document)
        guard let value = hooks["Stop"] else { return [] }
        guard let groups = value as? [[String: Any]] else { throw ConfigurationError.invalidHooks(file) }
        return groups
    }

    private func commands(in group: [String: Any]) -> [[String: Any]] {
        group["hooks"] as? [[String: Any]] ?? []
    }

    private func isCurrentChorusCommand(_ hook: [String: Any]) -> Bool {
        hook["type"] as? String == "command"
            && hook["command"] as? String == command
    }

    private func isOwnedChorusCommand(_ hook: [String: Any]) -> Bool {
        guard hook["type"] as? String == "command", let command = hook["command"] as? String else { return false }
        let suffix = "' " + source.rawValue
        guard command.hasPrefix("'"), command.hasSuffix(suffix) else { return false }
        let path = command.dropFirst().dropLast(suffix.count)
        return path.hasSuffix("/Contents/Helpers/chorus-hook")
    }

    private func removingChorusCommands(from groups: [[String: Any]]) -> [[String: Any]] {
        groups.compactMap { original in
            guard let existing = original["hooks"] as? [[String: Any]] else { return original }
            let retained = existing.filter { !isOwnedChorusCommand($0) }
            guard !retained.isEmpty else { return nil }
            var group = original
            group["hooks"] = retained
            return group
        }
    }

    private func write(_ document: [String: Any]) throws {
        let manager = FileManager.default
        let parent = file.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        let permissions = (try? manager.attributesOfItem(atPath: file.path)[.posixPermissions]) ?? 0o600
        let data = try JSONSerialization.data(withJSONObject: document,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: file, options: .atomic)
        try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: file.path)
    }

    private static func formattedJSON(_ value: [String: Any]) -> String {
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(data: try! JSONSerialization.data(withJSONObject: value, options: options), encoding: .utf8)!
    }

    public enum ConfigurationError: LocalizedError {
        case invalidJSON(URL)
        case invalidHooks(URL)

        public var errorDescription: String? {
            switch self {
            case .invalidJSON(let file): return "\(file.path) is not a valid JSON settings file."
            case .invalidHooks(let file): return "\(file.path) contains an unsupported hooks structure."
            }
        }
    }
}
