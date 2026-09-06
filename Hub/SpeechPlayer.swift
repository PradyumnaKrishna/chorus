import AVFoundation
import SwiftUI

@MainActor
final class SpeechPlayer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    enum State { case idle, speaking, paused }
    @Published private(set) var state: State = .idle
    @Published private(set) var voices: [AVSpeechSynthesisVoice] = []
    @Published private(set) var spokenText = ""
    @Published private(set) var wordRange: NSRange?
    @Published var error: String?
    @Published var selection: String = UserDefaults.standard.string(forKey: "voice") ?? "" {
        didSet { UserDefaults.standard.set(selection, forKey: "voice") }
    }
    @Published var rate: Double = UserDefaults.standard.object(forKey: "rate") as? Double ?? 0.5 {
        didSet { UserDefaults.standard.set(rate, forKey: "rate") }
    }
    private let synthesizer = AVSpeechSynthesizer()
    private var current: AVSpeechUtterance?
    // Only Apple's built-in voices provide word callbacks we can trust for highlighting.
    @Published private(set) var playbackCapabilities = VoiceCapabilities.basic
    var wordHighlighting: Bool { playbackCapabilities.wordHighlighting }
    var selectedCapabilities: VoiceCapabilities { VoiceCapabilities.forVoice(selection) }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    @Published private(set) var refreshing = false

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        // Provider discovery can launch extension processes. Never hold up the first window draw.
        Task {
            let available = await Task.detached(priority: .userInitiated) {
                AVSpeechSynthesisProviderVoice.updateSpeechVoices()
                return AVSpeechSynthesisVoice.speechVoices()
                    .sorted { ($0.language, $0.name) < ($1.language, $1.name) }
            }.value
            voices = available
            if !voices.contains(where: { $0.identifier == selection }) {
                selection = voices.first(where: { VoiceSource.identify($0.identifier) == .kokoro })?.identifier
                    ?? voices.first(where: { $0.identifier == AVSpeechSynthesisVoice(language: Locale.current.identifier)?.identifier })?.identifier
                    ?? voices.first?.identifier ?? ""
            }
            refreshing = false
        }
    }

    var kokoroVoiceCount: Int { voices.filter { VoiceSource.identify($0.identifier) == .kokoro }.count }
    var appleVoiceCount: Int { voices.filter { VoiceSource.identify($0.identifier) == .apple }.count }

    func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        let source = VoiceSource.identify(voice.identifier)
        // Older installed companions still register names with the Chorus prefix.
        let name = source == .kokoro && voice.name.hasPrefix("Chorus ")
            ? String(voice.name.dropFirst("Chorus ".count)) : voice.name
        return "\(name) · \(voice.language) · \(source.rawValue)"
    }

    @discardableResult
    func speak(_ text: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let voice = voices.first(where: { $0.identifier == selection }) else {
            error = "Select an available voice first. Refresh voices if the list is empty."
            return false
        }
        stop()
        error = nil
        spokenText = text
        playbackCapabilities = VoiceCapabilities.forVoice(voice.identifier)
        // Keep the complete passage in one request. The provider prepares future audio
        // chunks while this request plays; restarting per sentence discards that advantage.
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = Float(min(0.65, max(0.35, rate)))
        current = utterance
        state = .speaking
        synthesizer.speak(utterance)
        return true
    }

    func togglePause() {
        if state == .paused {
            if synthesizer.continueSpeaking() { state = .speaking }
        } else if state == .speaking {
            if synthesizer.pauseSpeaking(at: .immediate) { state = .paused }
        }
    }

    func stop() {
        // Clear identity first so delayed cancellation callbacks cannot reset a replacement utterance.
        current = nil
        synthesizer.stopSpeaking(at: .immediate)
        state = .idle
        wordRange = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identity = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard self.current.map(ObjectIdentifier.init) == identity else { return }
            self.current = nil
            self.state = .idle
            self.wordRange = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let identity = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard self.current.map(ObjectIdentifier.init) == identity else { return }
            self.current = nil
            self.state = .idle
            self.wordRange = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                      willSpeakRangeOfSpeechString characterRange: NSRange,
                                      utterance: AVSpeechUtterance) {
        // Carry only identity across the actor boundary, never the mutable framework object.
        let identity = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard self.current.map(ObjectIdentifier.init) == identity, self.wordHighlighting else { return }
            guard SpeechHighlight.range(characterRange, in: self.spokenText) != nil else { return }
            self.wordRange = characterRange
        }
    }
}
