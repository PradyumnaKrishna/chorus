import Foundation

/// Kokoro's estimated word markers are not suitable for reader captions.
struct VoiceCapabilities: Codable, Equatable {
    let wordHighlighting: Bool
    let fullPlayer: Bool

    static let basic = VoiceCapabilities(wordHighlighting: false, fullPlayer: false)
    static let system = VoiceCapabilities(wordHighlighting: true, fullPlayer: true)
    static let kokoro = basic

    static func forVoice(_ identifier: String) -> VoiceCapabilities {
        switch VoiceSource.identify(identifier) {
        case .kokoro: return .kokoro
        case .apple: return .system
        case .other: return VoiceCapabilities(wordHighlighting: false, fullPlayer: true)
        }
    }
}
