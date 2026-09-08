import Foundation
import Testing
@testable import ChorusIntegrationKit

@Test func codexCompletionRendersOnlyFinalAssistantText() throws {
    let payload: [String: Any] = [
        "hook_event_name": "Stop",
        "session_id": "one",
        "turn_id": "two",
        "last_assistant_message": "  # Done\n\nFixed **two** things 👋 नमस्ते.  "
    ]

    let event = try CompletionEvent.parse(
        JSONSerialization.data(withJSONObject: payload),
        source: .codex
    )

    #expect(event?.text == "Done\n\nFixed two things 👋 नमस्ते.")
    let encoded = try JSONEncoder().encode(event)
    #expect(try JSONDecoder().decode(CompletionEvent?.self, from: encoded)?.text == event?.text)
    #expect(try CompletionEvent.parse(
        JSONSerialization.data(withJSONObject: payload),
        source: .codex
    )?.id == event?.id)

    var nextTurn = payload
    nextTurn["turn_id"] = "three"
    #expect(try CompletionEvent.parse(
        JSONSerialization.data(withJSONObject: nextTurn),
        source: .codex
    )?.id != event?.id)
}

@Test func completionParserRejectsIrrelevantAndInvalidInput() throws {
    let approval = try payload(["type": "approval-requested", "last-assistant-message": "Approve"])
    #expect(try CompletionEvent.parse(approval, source: .codex) == nil)

    let subagent = try payload([
        "hook_event_name": "SubagentStop",
        "last_assistant_message": "Internal result"
    ])
    #expect(try CompletionEvent.parse(subagent, source: .claude) == nil)
    #expect(try CompletionEvent.parse(subagent, source: .codex) == nil)

    let empty = try payload(["hook_event_name": "Stop", "last_assistant_message": " \n "])
    #expect(try CompletionEvent.parse(empty, source: .claude) == nil)

    #expect(throws: CompletionEvent.InputError.tooLarge) {
        try CompletionEvent.parse(
            Data(repeating: 32, count: CompletionEvent.maximumBytes + 1),
            source: .claude
        )
    }
}

@Test func codexLegacyNotifyRemainsCompatible() throws {
    let data = try payload([
        "type": "agent-turn-complete",
        "thread-id": "one",
        "turn-id": "two",
        "last-assistant-message": "Legacy answer"
    ])

    #expect(try CompletionEvent.parse(data, source: .codex)?.text == "Legacy answer")
}

@Test func claudeCompletionUsesTheSameSpeechContract() throws {
    let data = try payload([
        "hook_event_name": "Stop",
        "session_id": "one",
        "last_assistant_message": "## Finished\n\nSee [the file](/tmp/file.swift)."
    ])

    #expect(try CompletionEvent.parse(data, source: .claude)?.text ==
            "Finished\n\nSee the file.")
}

private func payload(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object)
}
