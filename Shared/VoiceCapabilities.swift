import Foundation

/// What the reader may offer for a voice.
///
/// Word highlighting needs markers a voice places from its own timing. Kokoro
/// takes them from its model's predicted durations; an unknown provider is not
/// assumed to place any.
struct VoiceCapabilities: Codable, Equatable {
    let wordHighlighting: Bool
    let fullPlayer: Bool

    static let basic = VoiceCapabilities(wordHighlighting: false, fullPlayer: false)
    static let system = VoiceCapabilities(wordHighlighting: true, fullPlayer: true)
    static let kokoro = system

    static func forVoice(_ identifier: String) -> VoiceCapabilities {
        switch VoiceSource.identify(identifier) {
        case .kokoro: return .kokoro
        case .apple: return .system
        case .other: return VoiceCapabilities(wordHighlighting: false, fullPlayer: true)
        }
    }
}
