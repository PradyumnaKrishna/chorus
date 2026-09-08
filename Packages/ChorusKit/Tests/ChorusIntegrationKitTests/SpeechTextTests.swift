import Testing
@testable import ChorusIntegrationKit

@Test func rendersGitHubFlavoredMarkdownForSpeech() {
    let markdown = """
    # Completed

    - Fixed **two** bugs in [`SpeechPlayer`](/tmp/SpeechPlayer.swift:12).
    - [x] Kept snake_case and an escaped \\* character.

    | Harness | State |
    | --- | --- |
    | Codex | ready |

    ```swift
    let unhelpfulForSpeech = true
    ```
    ::code-comment{title="Internal UI metadata" file="/tmp/a" start=1}
    """

    #expect(SpeechText.render(markdown) == """
    Completed

    Fixed two bugs in SpeechPlayer.
    Kept snake_case and an escaped * character.

    Harness, State
    Codex, ready

    Code block omitted.
    """)
}

@Test func preservesReadableUnicodeAndDropsUnsafeMarkup() {
    #expect(SpeechText.render("\u{202E}Safe 👨‍👩‍👧‍👦") == "Safe 👨‍👩‍👧‍👦")
    #expect(SpeechText.render("Use <https://example.com> &amp; <em>docs</em>.") ==
            "Use https://example.com & docs.")
    #expect(SpeechText.render("Before ~~obsolete~~ after") == "Before after")
    #expect(SpeechText.render("<script>doBadThing()</script>").isEmpty)
    #expect(SpeechText.render("```swift\none\n```\n\n```swift\ntwo\n```") ==
            "Code block omitted.")
}

@Test func malformedMarkdownFailsClosedWithoutCrashing() {
    #expect(SpeechText.render("Before [unfinished link]( and text") ==
            "Before [unfinished link]( and text")
    #expect(SpeechText.render("```swift\nlet value = 1") == "Code block omitted.")
}

@Test func handlesInputNearTheCompletionBoundary() {
    let paragraph = String(repeating: "Readable text. ", count: 4_500)
    let rendered = SpeechText.render("# Result\n\n\(paragraph)")

    #expect(rendered.hasPrefix("Result\n\nReadable text."))
    #expect(rendered.utf8.count <= paragraph.utf8.count + 8)
}
