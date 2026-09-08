import Foundation
import ChorusIntegrationKit

// Hooks must never block a harness turn: no speech, transcript reads, or network work here.
do {
    let arguments = CommandLine.arguments
    guard arguments.count >= 2, let source = Harness(rawValue: arguments[1]) else {
        throw CompletionEvent.InputError.invalid
    }
    let data: Data
    if source == .codex, arguments.count == 3 {
        // Legacy Codex `notify` passes the payload as the final argument.
        data = Data(arguments[2].utf8)
    } else {
        guard arguments.count == 2 else { throw CompletionEvent.InputError.invalid }
        data = FileHandle.standardInput.readData(ofLength: CompletionEvent.maximumBytes + 1)
    }
    if let event = try CompletionEvent.parse(data, source: source) {
        let directory = CompletionEvent.inbox
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent(event.id + ".json")
        try JSONEncoder().encode(event).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        // The running menu-bar app polls this inbox; delivery must not launch or reopen it.
    }
} catch {
    FileHandle.standardError.write(Data("Chorus: \(error.localizedDescription)\n".utf8))
}
// In particular, never emit Claude's exit code 2 (which blocks completion).
