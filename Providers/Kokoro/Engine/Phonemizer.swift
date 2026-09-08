import Foundation

/// Turns text into the IPA phoneme ids Kokoro was trained on.
///
/// espeak-ng does the grapheme-to-phoneme work; the surrounding split and
/// substitution rules mirror the reference Kokoro phonemizer so the phoneme
/// strings match what the model expects.
/// Safe to share because every stored property is read and written only while
/// `lock` is held, and espeak-ng itself is serialized behind that same lock.
final class Phonemizer: @unchecked Sendable {

    /// espeak-ng keeps global state, so all use is funnelled through one instance.
    static let shared = Phonemizer()

    private let lock = NSLock()
    private var ready = false
    private var vocab: [Character: Int] = [:]

    private init() {}

    enum Error: Swift.Error, LocalizedError {
        case espeakInit
        case missingResource(String)

        var errorDescription: String? {
            switch self {
            case .espeakInit: return "espeak-ng failed to initialise"
            case .missingResource(let name): return "missing bundled resource: \(name)"
            }
        }
    }

    /// `dataDirectory` must contain `espeak-ng-data`.
    func prepare(dataDirectory: URL, tokenizer: URL) throws {
        lock.lock(); defer { lock.unlock() }
        guard !ready else { return }

        guard espeak_Initialize(AUDIO_OUTPUT_SYNCHRONOUS, 0, dataDirectory.path, 0) >= 0 else {
            throw Error.espeakInit
        }

        // tokenizer.json carries the 115-symbol phoneme table.
        guard let data = try? Data(contentsOf: tokenizer),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = root["model"] as? [String: Any],
              let table = model["vocab"] as? [String: Int]
        else { throw Error.missingResource(tokenizer.lastPathComponent) }

        vocab = table.reduce(into: [:]) { result, entry in
            if let symbol = entry.key.first, entry.key.count == 1 { result[symbol] = entry.value }
        }
        ready = true
    }

    /// Phoneme ids for `text`, or an empty array if nothing is speakable.
    func tokenize(_ text: String, language: KokoroLanguage) -> [Int] {
        align(text, language: language).tokens
    }

    /// Phoneme ids plus the source word behind each run of them.
    ///
    /// The ids are exactly what `tokenize` returns — both read the same phoneme
    /// string — so asking for the alignment cannot change what the model says.
    func align(_ text: String, language: KokoroLanguage) -> Alignment {
        // `phonemeText(for:)` takes `lock` internally and NSLock is not recursive,
        // so resolve the phonemes first and hold the lock only for the table read.
        let phonemes = phonemeText(for: text, language: language)
        lock.lock()
        defer { lock.unlock() }
        let tokenized = phonemes.tokens(using: vocab)
        return Alignment(tokens: tokenized.ids, words: tokenized.runs)
    }

    struct Alignment {
        let tokens: [Int]
        /// Spans of the requested text, each owning a run of consecutive tokens.
        let words: [MappedText.Run]
    }

    /// The IPA string Kokoro consumes. Exposed for debugging and tests.
    func phonemes(for text: String, language: KokoroLanguage) -> String {
        phonemeText(for: text, language: language).text
    }

    /// The same IPA string, with every phoneme attributed to the word it came from.
    func phonemeText(for text: String, language: KokoroLanguage) -> MappedText {
        let normalized = TextNormalizer.map(text)
        guard !normalized.isEmpty else { return MappedText() }

        // Punctuation is preserved verbatim: Kokoro uses it for prosody, and
        // handing it to espeak would lose it.
        var result = MappedText()
        var cursor = 0
        let characters = normalized.characters
        let source = normalized.text
        let punctuation = try! NSRegularExpression(
            pattern: #"(\s*[;:,.!?¡¿—…"«»“”(){}\[\]]+\s*)+"#)

        let range = NSRange(source.startIndex..., in: source)
        for match in punctuation.matches(in: source, range: range) {
            guard let matched = Range(match.range, in: source) else { continue }
            let lower = source.distance(from: source.startIndex, to: matched.lowerBound)
            let upper = source.distance(from: source.startIndex, to: matched.upperBound)
            if cursor < lower {
                append(characters[cursor..<lower], of: normalized, language: language, to: &result)
            }
            result.append(String(characters[lower..<upper]), origin: nil)
            cursor = upper
        }
        if cursor < characters.count {
            append(characters[cursor...], of: normalized, language: language, to: &result)
        }

        postProcess(&result, language: language)
        return result
    }

    /// Phonemizes one speakable run and appends it, attributing each
    /// whitespace-separated phoneme group to a word of that run.
    private func append(_ slice: ArraySlice<Character>, of normalized: MappedText,
                        language: KokoroLanguage, to result: inout MappedText) {
        let phonemes = espeak(String(slice), language)
        guard !phonemes.isEmpty else { return }

        let ranges = Self.wordRanges(in: slice)
        let attribution = Self.attribution(
            groups: phonemes.split(separator: " ").count,
            // espeak turns some words into several phonetic ones — "macOS" into
            // "mˈæk ˌoʊˈɛs" — so ask what each contributes on its own.
            counts: ranges.map { espeak(String(slice[$0]), language).split(separator: " ").count },
            words: ranges.map { normalized.origin(of: $0) })

        // Walk the phonemes rather than rejoining the groups, so the string the
        // model receives stays exactly what espeak produced.
        var group = 0
        var inGroup = false
        for character in phonemes {
            if character == " " {
                if inGroup { group += 1; inGroup = false }
                result.append(character, origin: nil)
            } else {
                inGroup = true
                result.append(character, origin: attribution.indices.contains(group) ? attribution[group] : nil)
            }
        }
    }

    /// Word ranges in the coordinates of the array `slice` was sliced from.
    private static func wordRanges(in slice: ArraySlice<Character>) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start: Int?
        for index in slice.indices {
            if slice[index].isWhitespace {
                if let begin = start { ranges.append(begin ..< index); start = nil }
            } else if start == nil {
                start = index
            }
        }
        if let begin = start { ranges.append(begin ..< slice.endIndex) }
        return ranges
    }

    /// The word each phoneme group of a clause belongs to.
    ///
    /// `counts` is how many groups each word produces alone. When they add up to
    /// what the clause produced the mapping is exact, even where one word became
    /// several; otherwise groups spread evenly, keeping any error in this clause.
    private static func attribution(groups: Int, counts: [Int],
                                    words: [Range<Int>?]) -> [Range<Int>?] {
        guard groups > 0, !words.isEmpty else { return [] }

        if counts.count == words.count, counts.reduce(0, +) == groups {
            return zip(words, counts).flatMap { Array(repeating: $0, count: $1) }
        }
        return (0 ..< groups).map { words[min($0 * words.count / groups, words.count - 1)] }
    }

    // MARK: - espeak-ng

    private func espeak(_ text: String, _ language: KokoroLanguage) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        lock.lock(); defer { lock.unlock() }
        guard ready else { return "" }
        _ = espeak_SetVoiceByName(language.espeakVoice)

        // espeak consumes the buffer one clause at a time, advancing the
        // pointer and dropping the boundary, so rejoin clauses with a space.
        // Phoneme mode 0x02 selects IPA output with no separator.
        var clauses: [String] = []
        trimmed.withCString { start in
            var cursor: UnsafeRawPointer? = UnsafeRawPointer(start)
            while cursor != nil {
                guard let output = espeak_TextToPhonemes(&cursor, Int32(espeakCHARS_UTF8), 0x02) else { break }
                let clause = String(cString: output).trimmingCharacters(in: .whitespaces)
                if !clause.isEmpty { clauses.append(clause) }
            }
        }
        return clauses.joined(separator: " ")
    }

    /// Maps espeak's output onto Kokoro's phoneme inventory.
    ///
    /// Applied to the joined string, as the rules were written: the trailing " z"
    /// rule can only be judged against its neighbours.
    private func postProcess(_ text: inout MappedText, language: KokoroLanguage) {
        // "kokoro" itself is mispronounced by espeak.
        for wrong in ["kəkˈoːɹoʊ", "kəkˈɔːɹoʊ"] {
            text.replace(NSRegularExpression.escapedPattern(for: wrong), with: "kˈoʊkəɹoʊ")
        }
        for wrong in ["kəkˈɔːɹəʊ", "kəkˈoːɹəʊ"] {
            text.replace(NSRegularExpression.escapedPattern(for: wrong), with: "kˈəʊkəɹəʊ")
        }

        // Symbols espeak emits that are outside Kokoro's vocabulary.
        for (from, to) in [("ʲ", "j"), ("r", "ɹ"), ("x", "k"), ("ɬ", "l")] {
            text.replace(NSRegularExpression.escapedPattern(for: from), with: to)
        }

        text.replace(#" z(?=[;:,.!?¡¿—…"«»“” ]|$)"#, with: "z")

        if language == .americanEnglish {
            text.replace(#"(?<=nˈaɪn)ti(?!ː)"#, with: "di")
        }

        text.trim()
    }
}
