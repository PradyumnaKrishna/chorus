import Foundation

/// Text in, 24 kHz mono float samples out.
final class KokoroEngine {

    /// Kokoro always runs at 24 kHz.
    static let sampleRate: Double = 24_000

    /// The model's positional limit, minus the two padding tokens.
    private static let maxTokens = 509

    private let model: OpaquePointer
    private let voicesDirectory: URL
    private var styleCache: [String: [Float]] = [:]
    private let cacheLock = NSLock()

    enum Error: Swift.Error, LocalizedError {
        case resources(String)
        case session(String)
        case inference(String)

        var errorDescription: String? {
            switch self {
            case .resources(let m): return "Kokoro resources unavailable: \(m)"
            case .session(let m):   return "Could not load the Kokoro model: \(m)"
            case .inference(let m): return "Kokoro synthesis failed: \(m)"
            }
        }
    }

    /// `resources` must contain kokoro.onnx, tokenizer.json, voices/ and espeak-ng-data/.
    init(resources: URL, modelURL: URL? = nil, useCoreML: Bool = false) throws {
        let model = modelURL ?? resources.appendingPathComponent("kokoro.onnx")
        let tokenizer = resources.appendingPathComponent("tokenizer.json")
        self.voicesDirectory = resources.appendingPathComponent("voices")

        for required in [model, tokenizer] where !FileManager.default.fileExists(atPath: required.path) {
            throw Error.resources(required.lastPathComponent)
        }

        try Phonemizer.shared.prepare(dataDirectory: resources, tokenizer: tokenizer)

        var error = [CChar](repeating: 0, count: 512)
        let threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 1))
        guard let handle = kokoro_ort_create(model.path, threads,
                                             useCoreML ? KOKORO_ORT_BACKEND_COREML : KOKORO_ORT_BACKEND_CPU,
                                             &error, error.count) else {
            throw Error.session(String(cString: error))
        }
        self.model = handle
    }

    deinit { kokoro_ort_destroy(model) }

    var voices: [KokoroVoice] { KokoroVoice.catalog(in: voicesDirectory) }

    func voice(withIdentifier identifier: String) -> KokoroVoice? {
        voices.first { $0.voiceIdentifier == identifier }
    }

    /// Synthesizes one span of text. Long text should be split with
    /// `chunkRanges(of:)` first so audio starts playing sooner.
    ///
    /// A span that still exceeds the model's positional limit is synthesized in
    /// several passes rather than clipped. `chunkRanges` budgets *characters*, on
    /// the assumption of roughly three per phoneme token, which does not hold for
    /// every script this provider ships; clipping here dropped the tail of the
    /// span silently, so speech simply stopped mid-sentence.
    func synthesize(_ text: String, voice: KokoroVoice, speed: Float = 1.0) throws -> [Float] {
        let ids = Phonemizer.shared.tokenize(text, language: voice.language)
        guard !ids.isEmpty else { return [] }

        guard ids.count > Self.maxTokens else {
            return try synthesize(tokens: ids, voice: voice, speed: speed)
        }

        var samples: [Float] = []
        for start in stride(from: 0, to: ids.count, by: Self.maxTokens) {
            let run = Array(ids[start ..< min(start + Self.maxTokens, ids.count)])
            samples.append(contentsOf: try synthesize(tokens: run, voice: voice, speed: speed))
        }
        return samples
    }

    /// One forward pass over a token run that is known to fit the positional limit.
    private func synthesize(tokens: [Int], voice: KokoroVoice, speed: Float) throws -> [Float] {
        let padded = [Int64(0)] + tokens.map(Int64.init) + [Int64(0)]
        let style = try styleVector(for: voice, tokenCount: tokens.count)

        var samples: UnsafeMutablePointer<Float>?
        var count = 0
        var error = [CChar](repeating: 0, count: 512)

        let status = padded.withUnsafeBufferPointer { idsBuffer in
            style.withUnsafeBufferPointer { styleBuffer in
                kokoro_ort_run(model,
                               idsBuffer.baseAddress, idsBuffer.count,
                               styleBuffer.baseAddress, styleBuffer.count,
                               max(0.1, speed),
                               &samples, &count,
                               &error, error.count)
            }
        }

        guard status == 0, let samples else { throw Error.inference(String(cString: error)) }
        defer { kokoro_ort_free(samples) }
        return Array(UnsafeBufferPointer(start: samples, count: count))
    }

    /// The style tensor is indexed by token count, so each voice file holds one
    /// 256-wide vector per possible sequence length.
    private func styleVector(for voice: KokoroVoice, tokenCount: Int) throws -> [Float] {
        let dimension = 256
        cacheLock.lock()
        var table = styleCache[voice.id]
        cacheLock.unlock()

        if table == nil {
            let url = voicesDirectory.appendingPathComponent("\(voice.id).bin")
            guard let data = try? Data(contentsOf: url) else {
                throw Error.resources("voices/\(voice.id).bin")
            }
            table = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            cacheLock.lock()
            styleCache[voice.id] = table
            cacheLock.unlock()
        }

        guard let table else { throw Error.resources("voices/\(voice.id).bin") }
        let index = min(max(tokenCount, 0), Self.maxTokens)
        let start = index * dimension
        guard start + dimension <= table.count else {
            throw Error.resources("voices/\(voice.id).bin is truncated")
        }
        return Array(table[start ..< start + dimension])
    }

    /// Splits text at sentence boundaries into spans that stay under the
    /// model's token limit, so playback can start before the whole passage has
    /// been synthesized.
    ///
    /// Ranges are character offsets into `text` rather than substrings, because
    /// callers need them to map audio back onto the original text.
    func chunkRanges(of text: String) -> [Range<Int>] {
        // Roughly three characters per phoneme token; stays well under the cap.
        let budget = 300
        let characters = Array(text)

        var sentences: [Range<Int>] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.bySentences, .localized]) { _, range, _, _ in
            let lower = text.distance(from: text.startIndex, to: range.lowerBound)
            let upper = text.distance(from: text.startIndex, to: range.upperBound)
            if lower < upper { sentences.append(lower..<upper) }
        }
        if sentences.isEmpty { sentences = [0..<characters.count] }

        var result: [Range<Int>] = []
        var current: Range<Int>?

        for sentence in sentences {
            if sentence.count > budget {
                if let open = current { result.append(open); current = nil }
                result.append(contentsOf: split(sentence, in: characters, budget: budget))
            } else if let open = current, sentence.upperBound - open.lowerBound > budget {
                result.append(open)
                current = sentence
            } else if let open = current {
                // Absorb any whitespace the enumeration skipped between sentences.
                current = open.lowerBound..<sentence.upperBound
            } else {
                current = sentence
            }
        }
        if let open = current { result.append(open) }

        return result.filter {
            !String(characters[$0]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Last-resort split, on whitespace, for a sentence with no usable boundary.
    private func split(_ range: Range<Int>, in characters: [Character], budget: Int) -> [Range<Int>] {
        var pieces: [Range<Int>] = []
        var start = range.lowerBound
        var lastSpace: Int?

        for index in range {
            if characters[index] == " " { lastSpace = index }
            if index - start >= budget, let space = lastSpace, space > start {
                pieces.append(start..<space)
                start = space + 1
                lastSpace = nil
            }
        }
        if start < range.upperBound { pieces.append(start..<range.upperBound) }
        return pieces
    }
}
