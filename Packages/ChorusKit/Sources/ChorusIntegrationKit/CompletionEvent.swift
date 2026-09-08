import CryptoKit
import Foundation

public enum Harness: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude, codex

    public var id: String { rawValue }
    public var title: String { self == .claude ? "Claude Code" : "Codex" }
}

/// A completed assistant response prepared for local speech delivery.
///
/// Prompts and transcripts never cross this boundary. The original response is
/// used only to derive a stable delivery identity; persisted text is speech-safe.
public struct CompletionEvent: Codable, Identifiable, Sendable {
    public let id: String
    public let source: Harness
    public let text: String
    public let createdAt: Date

    public static let maximumBytes = 65_536

    public static func parse(_ data: Data, source: Harness) throws -> CompletionEvent? {
        guard data.count <= maximumBytes else { throw InputError.tooLarge }
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InputError.invalid
        }

        guard let completion = source.payloadAdapter.completion(from: payload) else { return nil }
        let rawText = completion.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else { return nil }
        let text = SpeechText.render(rawText)
        guard !text.isEmpty, text.utf8.count <= maximumBytes else { return nil }

        // Delivery identity belongs to the harness response, not its lossy speech rendering.
        let identity = try JSONEncoder().encode([
            source.rawValue,
            completion.session,
            completion.turn,
            rawText,
        ])
        let id = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
        return CompletionEvent(id: id, source: source, text: text, createdAt: Date())
    }

    public enum InputError: LocalizedError, Sendable {
        case tooLarge, invalid

        public var errorDescription: String? {
            self == .tooLarge ? "Completion payload exceeds 64 KiB." : "Expected a JSON object."
        }
    }

    public static var inbox: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Chorus/Inbox", isDirectory: true)
    }
}

private struct CompletionPayload {
    let message: String
    let session: String
    let turn: String
}

private protocol CompletionPayloadAdapter {
    func completion(from payload: [String: Any]) -> CompletionPayload?
}

private struct CodexPayloadAdapter: CompletionPayloadAdapter {
    func completion(from payload: [String: Any]) -> CompletionPayload? {
        if let hookEvent = payload["hook_event_name"] as? String {
            guard hookEvent == "Stop",
                  let message = payload["last_assistant_message"] as? String else { return nil }
            return CompletionPayload(
                message: message,
                session: payload["session_id"] as? String ?? "",
                turn: payload["turn_id"] as? String ?? ""
            )
        }

        // Keep existing `notify` installations working while new installs use Stop hooks.
        guard payload["type"] as? String == "agent-turn-complete",
              let message = payload["last-assistant-message"] as? String else { return nil }
        return CompletionPayload(message: message,
                                 session: payload["thread-id"] as? String ?? "",
                                 turn: payload["turn-id"] as? String ?? "")
    }
}

private struct ClaudePayloadAdapter: CompletionPayloadAdapter {
    func completion(from payload: [String: Any]) -> CompletionPayload? {
        guard payload["hook_event_name"] as? String == "Stop",
              let message = payload["last_assistant_message"] as? String else { return nil }
        return CompletionPayload(
            message: message,
            session: payload["session_id"] as? String ?? "",
            turn: ""
        )
    }
}

private extension Harness {
    var payloadAdapter: any CompletionPayloadAdapter {
        switch self {
        case .claude: return ClaudePayloadAdapter()
        case .codex: return CodexPayloadAdapter()
        }
    }
}
