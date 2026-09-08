import Foundation

let arguments = CommandLine.arguments
let loading = Date()
let engine = try KokoroEngine(
    resources: URL(fileURLWithPath: arguments[1]),
    modelURL: URL(fileURLWithPath: arguments[2])
)
print(String(format: "model load: %.2fs", Date().timeIntervalSince(loading)))
let text = arguments[3]
guard let voice = engine.voices.first(where: { $0.id == arguments[4] }) else {
    fatalError("unknown voice; available: \(engine.voices.map(\.id).joined(separator: ", "))")
}

print("voices available: \(engine.voices.count)")
print("word timing: \(engine.publishesWordTiming ? "published by this model" : "unavailable — this model has no durations output")")
print("phonemes: \(Phonemizer.shared.phonemes(for: text, language: voice.language))")

let started = Date()
let characters = Array(text)
var samples: [Float] = []
/// Word spans in the finished audio, as the audio unit would publish them.
var words: [(text: String, samples: Range<Int>)] = []

let ranges = engine.chunkRanges(of: text)
for (index, range) in ranges.enumerated() {
    let chunkStart = Date()
    let chunk = String(characters[range])
    var result = try engine.synthesize(chunk, voice: voice)
    // Mirror the audio unit: trim, then move the offsets onto the played buffer.
    let trimmed = KokoroAudio.trimPadding(&result.samples, chunkText: chunk,
                                          hasFollowingChunk: index + 1 < ranges.count)
    let base = samples.count
    for word in result.words {
        let start = max(0, word.samples.lowerBound - trimmed)
        guard start < result.samples.count else { continue }
        let end = min(result.samples.count, max(start, word.samples.upperBound - trimmed))
        let source = (range.lowerBound + word.source.lowerBound) ..< (range.lowerBound + word.source.upperBound)
        words.append((String(characters[source]), (base + start) ..< (base + end)))
    }
    samples.append(contentsOf: result.samples)
    print(String(format: "chunk %d: %.2fs audio in %.2fs, %d words timed", index + 1,
                 Double(result.samples.count) / KokoroEngine.sampleRate,
                 Date().timeIntervalSince(chunkStart), result.words.count))
}
let elapsed = Date().timeIntervalSince(started)
let duration = Double(samples.count) / KokoroEngine.sampleRate
print(String(format: "audio: %.2fs  synthesis: %.2fs  realtime factor: %.2f",
             duration, elapsed, elapsed / max(duration, 0.001)))
print(String(format: "peak: %.3f", samples.map(abs).max() ?? 0))

if words.isEmpty {
    print("no words were timed")
} else {
    var previous = 0
    for word in words {
        precondition(word.samples.lowerBound >= previous, "word timings must not run backwards")
        precondition(word.samples.upperBound <= samples.count, "word timings must stay inside the audio")
        previous = word.samples.lowerBound
        print(String(format: "  %6.2f–%6.2fs  %@",
                     Double(word.samples.lowerBound) / KokoroEngine.sampleRate,
                     Double(word.samples.upperBound) / KokoroEngine.sampleRate,
                     word.text))
    }
    let timings = words.map {
        ["text": $0.text,
         "start": Double($0.samples.lowerBound) / KokoroEngine.sampleRate,
         "end": Double($0.samples.upperBound) / KokoroEngine.sampleRate] as [String: Any]
    }
    let json = try JSONSerialization.data(withJSONObject: timings, options: [.prettyPrinted])
    try json.write(to: URL(fileURLWithPath: "/tmp/kokoro-test.json"))
    print("wrote /tmp/kokoro-test.json (\(words.count) words)")
}

var pcm = Data()
for sample in samples {
    withUnsafeBytes(of: Int16(max(-1, min(1, sample)) * 32767).littleEndian) {
        pcm.append(contentsOf: $0)
    }
}
var header = Data("RIFF".utf8)
func appendUInt32(_ value: UInt32) {
    withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
}
func appendUInt16(_ value: UInt16) {
    withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
}
appendUInt32(UInt32(36 + pcm.count))
header.append(Data("WAVEfmt ".utf8))
appendUInt32(16)
appendUInt16(1)
appendUInt16(1)
appendUInt32(24_000)
appendUInt32(48_000)
appendUInt16(2)
appendUInt16(16)
header.append(Data("data".utf8))
appendUInt32(UInt32(pcm.count))
try (header + pcm).write(to: URL(fileURLWithPath: "/tmp/kokoro-test.wav"))
print("wrote /tmp/kokoro-test.wav")
