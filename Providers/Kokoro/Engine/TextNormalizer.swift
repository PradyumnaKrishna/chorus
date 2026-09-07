import Foundation

/// Text clean-up applied before phonemization.
///
/// This is a port of the normalisation step from the reference Kokoro
/// implementation. Kokoro was trained on text that had been through these
/// rules, so skipping them measurably degrades how numbers, currency and
/// abbreviations are read out.
enum TextNormalizer {

    static func normalize(_ input: String) -> String {
        var text = input

        // 1. Quotes and brackets. Parentheses become guillemets so that the
        //    punctuation splitter can treat them as a single class later.
        text = text.replacingOccurrences(of: "[‘’]", with: "'", options: .regularExpression)
        text = text.replacingOccurrences(of: "«", with: "“")
        text = text.replacingOccurrences(of: "»", with: "”")
        text = text.replacingOccurrences(of: "[“”]", with: "\"", options: .regularExpression)
        text = text.replacingOccurrences(of: "(", with: "«")
        text = text.replacingOccurrences(of: ")", with: "»")

        // 2. Full-width CJK punctuation to its ASCII equivalent.
        for (from, to) in [("、", ", "), ("。", ". "), ("！", "! "),
                           ("，", ", "), ("：", ": "), ("；", "; "), ("？", "? ")] {
            text = text.replacingOccurrences(of: from, with: to)
        }

        // 3. Whitespace.
        text = regexReplace(text, #"[^\S \n]"#, with: " ")
        text = regexReplace(text, #"  +"#, with: " ")
        text = regexReplace(text, #"(?<=\n) +(?=\n)"#, with: "")

        // 4. Abbreviations that espeak would otherwise spell out or clip.
        text = regexReplace(text, #"\bD[Rr]\.(?= [A-Z])"#, with: "Doctor")
        text = regexReplace(text, #"\b(?:Mr\.|MR\.(?= [A-Z]))"#, with: "Mister")
        text = regexReplace(text, #"\b(?:Ms\.|MS\.(?= [A-Z]))"#, with: "Miss")
        text = regexReplace(text, #"\b(?:Mrs\.|MRS\.(?= [A-Z]))"#, with: "Mrs")
        text = regexReplace(text, #"\betc\.(?! [A-Z])"#, with: "etc", options: [.caseInsensitive])

        // 5. Casual spellings.
        text = regexReplace(text, #"\b(y)eah?\b"#, with: "$1e'a", options: [.caseInsensitive])

        // 6. Numbers, times, years and currency.
        // Protect dotted versions before decimal matching consumes adjacent parts
        // (0.1.1 used to become "0 point 1.1", losing a spoken separator).
        text = regexReplaceMap(text, #"\b[vV]?\d+(?:\.\d+){2,}\b"#) { version in
            let prefixed = version.first == "v" || version.first == "V"
            let number = prefixed ? String(version.dropFirst()) : version
            return (prefixed ? "version " : "") + number.components(separatedBy: ".").joined(separator: " point ")
        }
        text = regexReplaceMap(text, #"\d*\.\d+|\b\d{4}s?\b|(?<!:)\b(?:[1-9]|1[0-2]):[0-5]\d\b(?!:)"#, splitNumber)
        text = regexReplace(text, #"(?<=\d),(?=\d)"#, with: "")
        text = regexReplaceMap(text,
            #"[$£]\d+(?:\.\d+)?(?: hundred| thousand| (?:[bm]|tr)illion)*\b|[$£]\d+\.\d\d?\b"#,
            options: [.caseInsensitive], flipMoney)
        text = regexReplaceMap(text, #"\d*\.\d+"#, pointNumber)
        text = regexReplace(text, #"(?<=\d)-(?=\d)"#, with: " to ")
        text = regexReplace(text, #"(?<=\d)S"#, with: " S")

        // 7. Possessives: force the 's onto the preceding consonant.
        text = regexReplace(text, #"(?<=[BCDFGHJ-NP-TV-Z])'?s\b"#, with: "'S")
        text = regexReplace(text, #"(?<=X')S\b"#, with: "s")

        // 8. Initialisms: "U.S. a" -> "U-S- a", "N.A.S.A" -> "N-A-S-A".
        text = regexReplaceMap(text, #"(?:[A-Za-z]\.){2,} [a-z]"#) {
            $0.replacingOccurrences(of: ".", with: "-")
        }
        text = regexReplace(text, #"(?<=[A-Z])\.(?=[A-Z])"#, with: "-", options: [.caseInsensitive])

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Number handling

    /// Reads 4-digit runs as years ("1995" -> "19 95") and h:mm as clock times.
    private static func splitNumber(_ match: String) -> String {
        if match.contains(".") { return match }

        if match.contains(":") {
            let parts = match.split(separator: ":")
            guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return match }
            if m == 0 { return "\(h) o'clock" }
            if m < 10 { return "\(h) oh \(m)" }
            return "\(h) \(m)"
        }

        guard match.count >= 4, let year = Int(match.prefix(4)) else { return match }
        if year < 1100 || year % 1000 < 10 { return match }

        let left = String(match.prefix(2))
        let right = Int(match.dropFirst(2).prefix(2)) ?? 0
        let suffix = match.hasSuffix("s") ? "s" : ""

        if (100...999).contains(year % 1000) {
            if right == 0 { return "\(left) hundred\(suffix)" }
            if right < 10 { return "\(left) oh \(right)\(suffix)" }
        }
        return "\(left) \(right)\(suffix)"
    }

    /// "$1.50" -> "1 dollar and 50 cents".
    private static func flipMoney(_ match: String) -> String {
        guard let symbol = match.first else { return match }
        let bill = symbol == "$" ? "dollar" : "pound"
        let amount = String(match.dropFirst())

        if Double(amount) == nil { return "\(amount) \(bill)s" }
        if !amount.contains(".") {
            return "\(amount) \(bill)\(amount == "1" ? "" : "s")"
        }

        let parts = amount.split(separator: ".", maxSplits: 1)
        let whole = String(parts[0])
        let cents = Int(String(parts.count > 1 ? parts[1] : "0").padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0
        let coins = symbol == "$" ? (cents == 1 ? "cent" : "cents")
                                  : (cents == 1 ? "penny" : "pence")
        return "\(whole) \(bill)\(whole == "1" ? "" : "s") and \(cents) \(coins)"
    }

    /// "3.14" -> "3 point 1 4".
    private static func pointNumber(_ match: String) -> String {
        let parts = match.split(separator: ".", maxSplits: 1)
        guard parts.count == 2 else { return match }
        return "\(parts[0]) point \(parts[1].map(String.init).joined(separator: " "))"
    }

    // MARK: - Regex helpers

    private static func regexReplace(_ text: String, _ pattern: String, with template: String,
                                     options: NSRegularExpression.Options = []) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        return re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                           withTemplate: template)
    }

    /// Replaces each match with the result of `transform`, walking backwards so
    /// that earlier ranges stay valid as we mutate the string.
    private static func regexReplaceMap(_ text: String, _ pattern: String,
                                        options: NSRegularExpression.Options = [],
                                        _ transform: (String) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        var result = text
        let matches = re.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: transform(String(result[range])))
        }
        return result
    }

}
