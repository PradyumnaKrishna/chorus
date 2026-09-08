import Foundation

/// Text that remembers where each of its characters came from.
///
/// Kokoro rewrites text in stages before the model sees it, but highlighting has
/// to point back at words the reader can see. Every stage is a regular-expression
/// replacement, so a replacement's characters all inherit the span of the match
/// they replaced. `nil` marks a character belonging to no word, such as the
/// punctuation the phonemizer passes through verbatim.
struct MappedText {
    private(set) var characters: [Character]
    /// Parallel to `characters`. Offsets index the text this mapping started from.
    private(set) var origins: [Range<Int>?]

    init(_ text: String) {
        characters = Array(text)
        origins = characters.indices.map { $0 ..< $0 + 1 }
    }

    init() {
        characters = []
        origins = []
    }

    var text: String { String(characters) }
    var isEmpty: Bool { characters.isEmpty }

    mutating func append(_ character: Character, origin: Range<Int>?) {
        characters.append(character)
        origins.append(origin)
    }

    mutating func append(_ text: some StringProtocol, origin: Range<Int>?) {
        for character in text { append(character, origin: origin) }
    }

    /// The span of the original text `range` came from, or nil when none of it
    /// has an origin.
    func origin(of range: Range<Int>) -> Range<Int>? {
        guard !range.isEmpty, range.lowerBound >= 0, range.upperBound <= origins.count else { return nil }
        let spans = origins[range].compactMap { $0 }
        guard let lower = spans.map(\.lowerBound).min(),
              let upper = spans.map(\.upperBound).max() else { return nil }
        return lower ..< upper
    }

    /// Mirrors `trimmingCharacters(in: .whitespacesAndNewlines)`.
    mutating func trim() {
        var start = 0
        var end = characters.count
        while start < end, characters[start].isWhitespace { start += 1 }
        while end > start, characters[end - 1].isWhitespace { end -= 1 }
        guard start > 0 || end < characters.count else { return }
        characters = Array(characters[start ..< end])
        origins = Array(origins[start ..< end])
    }

    /// Replaces every match of `pattern`, expanding `$1`-style group references.
    mutating func replace(_ pattern: String, with template: String,
                          options: NSRegularExpression.Options = []) {
        apply(pattern, options) { expression, match, text in
            expression.replacementString(for: match, in: text, offset: 0, template: template)
        }
    }

    mutating func replace(_ pattern: String, options: NSRegularExpression.Options = [],
                          _ transform: (String) -> String) {
        apply(pattern, options) { _, match, text in
            transform((text as NSString).substring(with: match.range))
        }
    }

    private mutating func apply(
        _ pattern: String,
        _ options: NSRegularExpression.Options,
        _ replacement: (NSRegularExpression, NSTextCheckingResult, String) -> String
    ) {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let text = self.text
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return }

        // NSRegularExpression measures in UTF-16 while this buffer is indexed by
        // Character, so translate the boundaries once rather than per match.
        var boundary: [Int: Int] = [:]
        var unit = 0
        for (index, character) in characters.enumerated() {
            boundary[unit] = index
            unit += String(character).utf16.count
        }
        boundary[unit] = characters.count

        var replacedCharacters: [Character] = []
        var replacedOrigins: [Range<Int>?] = []
        var cursor = 0
        for match in matches {
            guard let lower = boundary[match.range.location],
                  let upper = boundary[NSMaxRange(match.range)],
                  cursor <= lower, lower < upper else { continue }
            replacedCharacters.append(contentsOf: characters[cursor ..< lower])
            replacedOrigins.append(contentsOf: origins[cursor ..< lower])

            let origin = origin(of: lower ..< upper)
            for character in replacement(expression, match, text) {
                replacedCharacters.append(character)
                replacedOrigins.append(origin)
            }
            cursor = upper
        }
        replacedCharacters.append(contentsOf: characters[cursor...])
        replacedOrigins.append(contentsOf: origins[cursor...])
        characters = replacedCharacters
        origins = replacedOrigins
    }

    /// A run of consecutive tokens that share one origin.
    struct Run: Equatable {
        /// Indices into the id array returned alongside it.
        let tokens: Range<Int>
        /// The span of the original text those tokens came from.
        let source: Range<Int>
    }

    /// Maps characters to ids through `vocabulary`, dropping any the model has no
    /// symbol for, and groups them into runs sharing one origin — so "$1.50" is a
    /// single run for as long as "one dollar and fifty cents" takes to say.
    func tokens(using vocabulary: [Character: Int]) -> (ids: [Int], runs: [Run]) {
        var ids: [Int] = []
        var runs: [Run] = []
        var openSource: Range<Int>?
        var openStart = 0

        for (index, character) in characters.enumerated() {
            guard let id = vocabulary[character] else { continue }
            let origin = origins[index]
            if let source = openSource, source != origin {
                runs.append(Run(tokens: openStart ..< ids.count, source: source))
                openSource = nil
            }
            if openSource == nil, let origin {
                openSource = origin
                openStart = ids.count
            }
            ids.append(id)
        }
        if let source = openSource {
            runs.append(Run(tokens: openStart ..< ids.count, source: source))
        }
        return (ids, runs)
    }
}
