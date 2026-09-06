import Foundation
import CryptoKit

enum Harness: String, Codable, CaseIterable, Identifiable {
    case claude, codex
    var id: String { rawValue }
    var title: String { self == .claude ? "Claude Code" : "Codex" }
}

/// Only completed assistant text crosses the hook boundary; prompts and transcripts stay in the harness.
struct CompletionEvent: Codable, Identifiable {
    let id: String
    let source: Harness
    let text: String
    let createdAt: Date
    static let maximumBytes = 65_536

    static func parse(_ data: Data, source: Harness) throws -> CompletionEvent? {
        guard data.count <= maximumBytes else { throw InputError.tooLarge }
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InputError.invalid
        }
        let message: String?
        let session: String
        let turn: String
        switch source {
        case .claude:
            guard payload["hook_event_name"] as? String == "Stop" else { return nil }
            message = payload["last_assistant_message"] as? String
            session = payload["session_id"] as? String ?? ""
            turn = ""
        case .codex:
            guard payload["type"] as? String == "agent-turn-complete" else { return nil }
            message = payload["last-assistant-message"] as? String
            session = payload["thread-id"] as? String ?? ""
            turn = payload["turn-id"] as? String ?? ""
        }
        guard let text = message?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let identity = try JSONEncoder().encode([source.rawValue, session, turn, text])
        let id = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
        return CompletionEvent(id: id, source: source, text: text, createdAt: Date())
    }

    enum InputError: LocalizedError {
        case tooLarge, invalid
        var errorDescription: String? {
            self == .tooLarge ? "Completion payload exceeds 64 KiB." : "Expected a JSON object."
        }
    }

    static var inbox: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Chorus/Inbox", isDirectory: true)
    }
}
