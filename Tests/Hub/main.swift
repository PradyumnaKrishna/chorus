import Foundation

func require(_ condition: Bool, _ message: String) {
    if !condition { fatalError(message) }
}
require(VoiceSource.identify("com.example.speech.provider.voice") == .other,
        "Unmanaged providers must not be treated as Chorus voices")
require(VoiceSource.identify("in.onpy.Chorus.Kokoro.Synthesizer.in.onpy.chorus.kokoro.af_bella") == .kokoro,
        "Current provider voices must be recognized")
require(VoiceSource.identify("com.apple.voice.compact.en-US.Samantha") == .apple,
        "Built-in voices must not count as installed Chorus voices")
let unicodeText = "Hello 👋🏽 café दुनिया"
let cafe = (unicodeText as NSString).range(of: "café")
require(SpeechHighlight.range(cafe, in: unicodeText).map { String(unicodeText[$0]) } == "café",
        "Highlighting must map UTF-16 callbacks after an emoji correctly")
require(SpeechHighlight.range(NSRange(location: 7, length: 1), in: unicodeText) == nil,
        "A range splitting an emoji must be ignored")
require(SpeechHighlight.range(NSRange(location: Int.max, length: 2), in: unicodeText) == nil,
        "Stale or invalid callbacks must not overflow or highlight unrelated text")
print("Voice compatibility and highlighting checks passed")

var selectionGate = SelectionGate()
let selected = SelectionGate.Snapshot(source: "editor", text: "Read this sentence.")
require(selectionGate.observe(selected, at: 0, interacting: true) == nil, "Dragging must not start speech")
require(selectionGate.observe(selected, at: 1, interacting: true) == nil, "Holding a selection must not restart speech")
require(selectionGate.observe(selected, at: 1.2, interacting: false) == nil, "Selection must settle before reading")
require(selectionGate.observe(selected, at: 1.7, interacting: false) == selected.text, "Settled selection must read")
require(selectionGate.observe(selected, at: 3, interacting: false) == nil, "An unchanged selection must not repeat after stop or completion")
_ = selectionGate.observe(nil, at: 4, interacting: false)
_ = selectionGate.observe(selected, at: 5, interacting: false)
require(selectionGate.observe(selected, at: 5.7, interacting: false) == selected.text, "Reselecting text must read it again")
_ = selectionGate.observe(.init(source: "other", text: "New text"), at: 6, interacting: false)
_ = selectionGate.observe(nil, at: 6.2, interacting: false)
require(selectionGate.observe(nil, at: 7, interacting: false) == nil, "Cleared selection must cancel pending speech")
print("Engine capabilities and selection debounce regressions passed")
