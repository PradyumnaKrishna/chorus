import AppKit
import Foundation

// Hooks must never block a harness turn: no speech, transcript reads, or network work here.
do {
    let arguments = CommandLine.arguments
    guard arguments.count >= 2, let source = Harness(rawValue: arguments[1]) else {
        throw CompletionEvent.InputError.invalid
    }
    let data: Data
    if source == .codex {
        guard arguments.count == 3 else { throw CompletionEvent.InputError.invalid }
        data = Data(arguments[2].utf8)
    } else {
        data = FileHandle.standardInput.readData(ofLength: CompletionEvent.maximumBytes + 1)
    }
    if let event = try CompletionEvent.parse(data, source: source) {
        let directory = CompletionEvent.inbox
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent(event.id + ".json")
        try JSONEncoder().encode(event).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        // The executable is shipped inside Chorus.app/Contents/Helpers.
        let app = URL(fileURLWithPath: arguments[0]).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        if app.pathExtension == "app" {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-g", app.path]
            try process.run()
        }
    }
} catch {
    FileHandle.standardError.write(Data("Chorus: \(error.localizedDescription)\n".utf8))
}
// In particular, never emit Claude's exit code 2 (which blocks completion).
