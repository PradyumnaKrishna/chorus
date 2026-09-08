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

    /// The paragraph `word` falls in.
    static func paragraph(around word: Range<String.Index>, in text: String) -> Range<String.Index> {
        let start = text[..<word.lowerBound].lastIndex(where: \.isNewline)
            .map { text.index(after: $0) } ?? text.startIndex
        let end = text[word.upperBound...].firstIndex(where: \.isNewline) ?? text.endIndex
        return start..<end
    }

    /// The span to show while `word` is spoken: a little context, beginning on a
    /// whole word, and never reaching outside the paragraph being read.
    ///
    /// A long lead-in pushes the spoken word to the end of the first line, leaving
    /// only what has already been read in view. Keeping it short puts that word
    /// early, with the text about to be read filling the rest. Snapping to a word
    /// start also means the excerpt moves a whole word at a time rather than
    /// sliding through one, and stopping at the paragraph keeps it from running the
    /// end of one into the start of the next.
    static func excerpt(around word: Range<String.Index>, in text: String,
                        context: Int = 22) -> Range<String.Index> {
        let paragraph = paragraph(around: word, in: text)
        guard let limit = text.index(word.lowerBound, offsetBy: -context, limitedBy: paragraph.lowerBound),
              limit > paragraph.lowerBound else { return paragraph }
        guard let space = text[limit..<word.lowerBound].firstIndex(where: \.isWhitespace) else {
            return word.lowerBound..<paragraph.upperBound
        }
        return text.index(after: space)..<paragraph.upperBound
    }
}
