import Foundation

/// UTF-16 code unit for an ASCII character.
private func ascii(_ scalar: Unicode.Scalar) -> UInt16 { UInt16(scalar.value) }

/// The plain text carried by an SSML request, plus the mapping back to the
/// original string.
///
/// Word markers must be expressed as ranges into `ssmlRepresentation`, so every
/// emitted character remembers where it came from. Only the subset of SSML that
/// AVSpeechSynthesizer actually emits is interpreted.
struct SSMLText {
    /// Text with markup removed.
    let text: String
    /// Original SSML spans for each extended grapheme cluster in `text`.
    let sourceRanges: [NSRange]
    /// Speaking rate from `<prosody rate="...">`, as a multiplier.
    let rate: Float
    /// Trailing silence requested by `<break time="...">`, in seconds.
    let trailingSilence: Double

    /// Range in the original SSML covering `range` of `text`.
    func ssmlRange(for range: Range<Int>) -> NSRange {
        guard !range.isEmpty, range.lowerBound >= 0, range.upperBound <= sourceRanges.count else {
            return NSRange(location: 0, length: 0)
        }
        let first = sourceRanges[range.lowerBound]
        let last = sourceRanges[range.upperBound - 1]
        return NSRange(location: first.location, length: NSMaxRange(last) - first.location)
    }

    static func parse(_ ssml: String) -> SSMLText {
        let scalars = Array(ssml.utf16)
        var output: [UInt16] = []
        var origins: [NSRange] = []
        var rate: Float = 1.0
        var silence: Double = 0

        var index = 0
        while index < scalars.count {
            let character = scalars[index]

            if character == ascii("<") {
                // Consume the tag, then interpret the few we care about.
                let start = index
                while index < scalars.count, scalars[index] != ascii(">") { index += 1 }
                if index < scalars.count { index += 1 }

                let tag = String(decoding: scalars[start..<index], as: UTF16.self)
                if let value = attribute("rate", in: tag) { rate *= parseRate(value) }
                if tag.hasPrefix("<break"), let value = attribute("time", in: tag) {
                    silence += parseDuration(value)
                }
                // A break also reads as a pause in the text itself.
                if tag.hasPrefix("<break") {
                    output.append(ascii(" "))
                    origins.append(NSRange(location: start, length: index - start))
                }
                continue
            }

            if character == ascii("&") {
                // Entity: &amp; &lt; &gt; &quot; &apos; &#NN;
                let start = index
                var end = index
                while end < scalars.count, scalars[end] != ascii(";"), end - start < 12 { end += 1 }
                if end < scalars.count, scalars[end] == ascii(";") {
                    let entity = String(decoding: scalars[start...end], as: UTF16.self)
                    if let decoded = decode(entity) {
                        for unit in decoded.utf16 {
                            output.append(unit)
                            origins.append(NSRange(location: start, length: end - start + 1))
                        }
                        index = end + 1
                        continue
                    }
                }
            }

            output.append(character)
            origins.append(NSRange(location: index, length: 1))
            index += 1
        }

        // Decode whole UTF-16 sequences before grouping characters; decoding one unit corrupts emoji.
        let text = String(decoding: output, as: UTF16.self)
        var sourceRanges: [NSRange] = []
        var unitOffset = 0
        for character in text {
            let count = String(character).utf16.count
            let first = origins[unitOffset]
            let last = origins[unitOffset + count - 1]
            sourceRanges.append(NSRange(location: first.location, length: NSMaxRange(last) - first.location))
            unitOffset += count
        }
        return SSMLText(text: text, sourceRanges: sourceRanges, rate: rate, trailingSilence: silence)
    }

    // MARK: - Attribute parsing

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\(name)\\s*=\\s*[\"']([^\"']*)[\"']"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = re.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              let range = Range(match.range(at: 1), in: tag)
        else { return nil }
        return String(tag[range])
    }

    /// Accepts "150%", "1.5", or the SSML keywords.
    private static func parseRate(_ value: String) -> Float {
        switch value.lowercased() {
        case "x-slow": return 0.5
        case "slow":   return 0.75
        case "medium", "default": return 1.0
        case "fast":   return 1.25
        case "x-fast": return 1.5
        default:
            if value.hasSuffix("%"), let percent = Float(value.dropLast()) { return percent / 100 }
            return Float(value) ?? 1.0
        }
    }

    /// Accepts "500ms" or "2s".
    private static func parseDuration(_ value: String) -> Double {
        if value.hasSuffix("ms"), let ms = Double(value.dropLast(2)) { return ms / 1000 }
        if value.hasSuffix("s"), let s = Double(value.dropLast()) { return s }
        return Double(value) ?? 0
    }

    private static func decode(_ entity: String) -> String? {
        switch entity {
        case "&amp;":  return "&"
        case "&lt;":   return "<"
        case "&gt;":   return ">"
        case "&quot;": return "\""
        case "&apos;": return "'"
        default:
            guard entity.hasPrefix("&#"), entity.hasSuffix(";") else { return nil }
            let digits = entity.dropFirst(2).dropLast()
            let value = digits.hasPrefix("x") || digits.hasPrefix("X")
                ? UInt32(digits.dropFirst(), radix: 16)
                : UInt32(digits)
            return value.flatMap(UnicodeScalar.init).map(String.init)
        }
    }
}
