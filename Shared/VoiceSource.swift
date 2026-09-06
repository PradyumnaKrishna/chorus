import Foundation

enum VoiceSource: String, CaseIterable {
    case kokoro = "Kokoro", apple = "macOS", other = "Other voices"

    static func identify(_ identifier: String) -> VoiceSource {
        // Provider identifiers are prefixed by their extension bundle ID by macOS.
        if identifier.contains("in.onpy.chorus.kokoro.") { return .kokoro }
        if identifier.hasPrefix("com.apple.") { return .apple }
        return .other
    }
}

/// Speech callbacks use UTF-16 offsets, not Swift Character counts. Reject partial graphemes and stale ranges.
enum SpeechHighlight {
    static func range(_ range: NSRange?, in text: String) -> Range<String.Index>? {
        guard let range, range.location != NSNotFound, range.length > 0,
              range.location <= text.utf16.count, range.length <= text.utf16.count - range.location,
              let result = Range(range, in: text),
              text.indices.contains(result.lowerBound),
              result.upperBound == text.endIndex || text.indices.contains(result.upperBound) else { return nil }
        return result
    }
}
