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
print("phonemes: \(Phonemizer.shared.phonemes(for: text, language: voice.language))")

let started = Date()
let characters = Array(text)
var samples: [Float] = []
for (index, range) in engine.chunkRanges(of: text).enumerated() {
    let chunkStart = Date()
    let audio = try engine.synthesize(String(characters[range]), voice: voice)
    samples.append(contentsOf: audio)
    print(String(format: "chunk %d: %.2fs audio in %.2fs", index + 1,
                 Double(audio.count) / KokoroEngine.sampleRate, Date().timeIntervalSince(chunkStart)))
}
let elapsed = Date().timeIntervalSince(started)
let duration = Double(samples.count) / KokoroEngine.sampleRate
print(String(format: "audio: %.2fs  synthesis: %.2fs  realtime factor: %.2f",
             duration, elapsed, elapsed / max(duration, 0.001)))
print(String(format: "peak: %.3f", samples.map(abs).max() ?? 0))

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
