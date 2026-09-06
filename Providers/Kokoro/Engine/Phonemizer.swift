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
        // `phonemes(for:)` takes `lock` internally and NSLock is not recursive,
        // so resolve the string first and hold the lock only for the table read.
        let phonemeString = phonemes(for: text, language: language)
        lock.lock()
        defer { lock.unlock() }
        return phonemeString.compactMap { vocab[$0] }
    }

    /// The IPA string Kokoro consumes. Exposed for debugging and tests.
    func phonemes(for text: String, language: KokoroLanguage) -> String {
        let normalized = TextNormalizer.normalize(text)
        guard !normalized.isEmpty else { return "" }

        // Punctuation is preserved verbatim: Kokoro uses it for prosody, and
        // handing it to espeak would lose it.
        var result = ""
        var cursor = normalized.startIndex
        let punctuation = try! NSRegularExpression(
            pattern: #"(\s*[;:,.!?¡¿—…"«»“”(){}\[\]]+\s*)+"#)

        let range = NSRange(normalized.startIndex..., in: normalized)
        for match in punctuation.matches(in: normalized, range: range) {
            guard let matched = Range(match.range, in: normalized) else { continue }
            if cursor < matched.lowerBound {
                result += espeak(String(normalized[cursor..<matched.lowerBound]), language)
            }
            result += normalized[matched]
            cursor = matched.upperBound
        }
        if cursor < normalized.endIndex {
            result += espeak(String(normalized[cursor...]), language)
        }

        return postProcess(result, language: language)
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
    private func postProcess(_ input: String, language: KokoroLanguage) -> String {
        var text = input

        // "kokoro" itself is mispronounced by espeak.
        for wrong in ["kəkˈoːɹoʊ", "kəkˈɔːɹoʊ"] {
            text = text.replacingOccurrences(of: wrong, with: "kˈoʊkəɹoʊ")
        }
        for wrong in ["kəkˈɔːɹəʊ", "kəkˈoːɹəʊ"] {
            text = text.replacingOccurrences(of: wrong, with: "kˈəʊkəɹəʊ")
        }

        // Symbols espeak emits that are outside Kokoro's vocabulary.
        for (from, to) in [("ʲ", "j"), ("r", "ɹ"), ("x", "k"), ("ɬ", "l")] {
            text = text.replacingOccurrences(of: from, with: to)
        }

        text = text.replacingOccurrences(
            of: #" z(?=[;:,.!?¡¿—…"«»“” ]|$)"#, with: "z", options: .regularExpression)

        if language == .americanEnglish {
            text = text.replacingOccurrences(
                of: #"(?<=nˈaɪn)ti(?!ː)"#, with: "di", options: .regularExpression)
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
