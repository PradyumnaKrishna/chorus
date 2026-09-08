import Foundation
import Testing
@testable import ChorusIntegrationKit

private let helper = URL(fileURLWithPath: "/Applications/Chorus.app/Contents/Helpers/chorus-hook")

@Test func preservesUnrelatedSettingsAndHooks() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let configuration = IntegrationConfiguration(source: .codex, executable: helper,
                                                 homeDirectory: home)
    try FileManager.default.createDirectory(at: configuration.file.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    let existing: [String: Any] = [
        "theme": "dark",
        "hooks": ["Stop": [["hooks": [["type": "command", "command": "backup"]]]]]
    ]
    try JSONSerialization.data(withJSONObject: existing).write(to: configuration.file)

    try configuration.install()
    #expect(try configuration.isInstalled())
    let installed = try document(at: configuration.file)
    #expect(installed["theme"] as? String == "dark")
    let hooks = installed["hooks"] as? [String: Any]
    let groups = hooks?["Stop"] as? [[String: Any]]
    let commands = groups?.first?["hooks"] as? [[String: Any]]
    #expect(commands?.first?["command"] as? String == "backup")
}

@Test func staleApplicationPathRequiresRepair() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let old = IntegrationConfiguration(source: .codex,
                                       executable: URL(fileURLWithPath: "/Old/Chorus.app/Contents/Helpers/chorus-hook"),
                                       homeDirectory: home)
    try old.install()

    let current = IntegrationConfiguration(source: .codex, executable: helper, homeDirectory: home)
    #expect(try !current.isInstalled())
    try current.install()
    #expect(try current.isInstalled())
    #expect(try !old.isInstalled())
}

@Test func rejectsUnsupportedHooksWithoutRewriting() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let configuration = IntegrationConfiguration(source: .claude, executable: helper,
                                                 homeDirectory: home)
    try FileManager.default.createDirectory(at: configuration.file.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    let original = Data("{\"hooks\":[]}".utf8)
    try original.write(to: configuration.file)

    #expect(throws: IntegrationConfiguration.ConfigurationError.self) {
        try configuration.install()
    }
    #expect(try Data(contentsOf: configuration.file) == original)
}

@Test func usesCustomConfigurationRoot() {
    let codex = IntegrationConfiguration(source: .codex, executable: helper,
                                         environment: ["CODEX_HOME": "/tmp/custom-codex"])
    let claude = IntegrationConfiguration(source: .claude, executable: helper,
                                          environment: ["CLAUDE_CONFIG_DIR": "/tmp/custom-claude"])

    #expect(codex.file.path == "/tmp/custom-codex/hooks.json")
    #expect(claude.file.path == "/tmp/custom-claude/settings.json")
}

private func document(at file: URL) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
}
