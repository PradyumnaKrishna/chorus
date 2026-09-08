import Foundation

func require(_ condition: Bool, _ message: String) {
    if !condition { fatalError(message) }
}

// MARK: - Normalization

// Kokoro was trained on text that had been through these rules, so these strings
// are part of the model's input contract, not formatting preferences.
let normalizations = [
    ("It cost $1.50.", "1 dollar and 50 cents."),
    ("Released in 1995.", "19 95."),
    ("Meet at 9:05.", "9 oh 5."),
    ("Chorus v0.1.1 shipped.", "Chorus version 0 point 1 point 1 shipped."),
    ("Dr. Smith called.", "Doctor Smith called."),
    ("Pi is 3.14.", "Pi is 3 point 1 4.")
]
for (input, expected) in normalizations {
    let actual = TextNormalizer.normalize(input)
    require(actual.contains(expected),
            "Normalizing \(input.debugDescription) must produce \(expected.debugDescription), got \(actual.debugDescription)")
}

// MARK: - Origins survive normalization

for (input, _) in normalizations {
    let mapped = TextNormalizer.map(input)
    require(mapped.text == TextNormalizer.normalize(input), "map and normalize must agree")
    var previous = -1
    for origin in mapped.origins {
        guard let origin else { fatalError("Normalization must not drop a character's origin") }
        require(origin.lowerBound >= 0 && origin.upperBound <= input.count,
                "An origin must stay inside the text it came from")
        require(origin.lowerBound >= previous, "Origins must not run backwards")
        previous = origin.lowerBound
    }
}

// An expansion attributes all of its output to the source it replaced, so "$1.50"
// stays highlighted for as long as it is being spoken.
let money = TextNormalizer.map("It cost $1.50.")
let dollars = money.text.range(of: "1 dollar and 50 cents")!
let start = money.text.distance(from: money.text.startIndex, to: dollars.lowerBound)
let end = money.text.distance(from: money.text.startIndex, to: dollars.upperBound)
require(money.origin(of: start ..< end) == 8 ..< 13,
        "Every character of an expansion must map back to the source it replaced")

// MARK: - Token runs

var phonemes = MappedText()
phonemes.append("hɛloʊ", origin: 0 ..< 5)
phonemes.append(" ", origin: nil)
phonemes.append("wɜɹld", origin: 6 ..< 11)
// Kokoro's table includes the space, so spacing is tokenized despite belonging
// to no word.
let vocabulary = Dictionary("hɛloʊwɜɹld ".map { ($0, Int($0.unicodeScalars.first!.value)) },
                            uniquingKeysWith: { first, _ in first })
let tokenized = phonemes.tokens(using: vocabulary)
require(tokenized.ids.count == 11, "Every vocabulary character must produce one token")
require(tokenized.runs == [MappedText.Run(tokens: 0 ..< 5, source: 0 ..< 5),
                          MappedText.Run(tokens: 6 ..< 11, source: 6 ..< 11)],
        "Tokens must group into one run per source word, skipping unattributed spacing")

let unknown = phonemes.tokens(using: ["h": 1, "w": 2])
require(unknown.ids == [1, 2], "Characters outside the vocabulary must be dropped")
require(unknown.runs == [MappedText.Run(tokens: 0 ..< 1, source: 0 ..< 5),
                        MappedText.Run(tokens: 1 ..< 2, source: 6 ..< 11)],
        "Dropped characters must not shift the token indices a run reports")

// MARK: - Marker ranges address the request the system sent

// Markers are ranges into the SSML document, not into the plain text the engine
// works on, so every emitted range must select the same word back in it.
let document = "<speak><prosody rate=\"1.0\">Hello world, R&amp;D is here.</prosody></speak>"
let ssml = SSMLText.parse(document)
require(ssml.text == "Hello world, R&D is here.", "Markup and entities must resolve to plain text")

for word in ["Hello", "world", "here"] {
    let found = ssml.text.range(of: word)!
    let range = ssml.ssmlRange(for: ssml.text.distance(from: ssml.text.startIndex, to: found.lowerBound)
                                ..< ssml.text.distance(from: ssml.text.startIndex, to: found.upperBound))
    require((document as NSString).substring(with: range) == word,
            "A marker for \(word) must select \(word) in the request document")
}

// A word covering an entity must select the whole entity it was written as.
let entity = ssml.text.range(of: "R&D")!
let entityRange = ssml.ssmlRange(for: ssml.text.distance(from: ssml.text.startIndex, to: entity.lowerBound)
                                  ..< ssml.text.distance(from: ssml.text.startIndex, to: entity.upperBound))
require((document as NSString).substring(with: entityRange) == "R&amp;D",
        "A marker spanning an entity must cover how it was written")

// MARK: - Frame durations to sample positions

// Two padding frames bracket three tokens; 40 frames spread over 400 samples.
let spans = SpeechAlignment.spans(frames: [3, 10, 20, 5, 2], totalSamples: 400)
require(spans == [30 ..< 130, 130 ..< 330, 330 ..< 380],
        "Spans must cover the unpadded tokens in proportion to their durations, got \(spans)")
require(SpeechAlignment.spans(frames: [1, 2], totalSamples: 100).isEmpty,
        "A pass with no unpadded tokens has no spans")
require(SpeechAlignment.spans(frames: [], totalSamples: 100).isEmpty,
        "A model publishing no durations must produce no spans")
require(SpeechAlignment.spans(frames: [0, 0, 0], totalSamples: 100).isEmpty,
        "Zero total duration must not divide by zero")

let timings = SpeechAlignment.timings(
    for: [MappedText.Run(tokens: 0 ..< 2, source: 0 ..< 5),
          MappedText.Run(tokens: 2 ..< 3, source: 6 ..< 11)],
    spans: spans)
require(timings == [WordTiming(source: 0 ..< 5, samples: 30 ..< 330),
                    WordTiming(source: 6 ..< 11, samples: 330 ..< 380)],
        "A word must span from its first token's start to its last token's end")
require(SpeechAlignment.timings(for: [MappedText.Run(tokens: 9 ..< 12, source: 0 ..< 5)],
                                spans: spans).isEmpty,
        "A run past the end of the pass must be dropped rather than trusted")

// A word espeak split into several phonetic words is highlighted once, across
// the whole time it takes to say.
let merged = SpeechAlignment.timings(
    for: [MappedText.Run(tokens: 0 ..< 1, source: 0 ..< 5),
          MappedText.Run(tokens: 1 ..< 3, source: 0 ..< 5)],
    spans: spans)
require(merged == [WordTiming(source: 0 ..< 5, samples: 30 ..< 380)],
        "Neighbouring runs naming one source must merge into a single span")

// MARK: - Trimming reports what it removed

var audio = [Float](repeating: 0, count: 5_000) + [Float](repeating: 0.5, count: 5_000)
let before = audio.count
let removed = KokoroAudio.trimPadding(&audio, chunkText: "hello", hasFollowingChunk: false)
require(removed == 5_000 - 960, "Trimming must report the leading samples it removed, got \(removed)")
require(audio.count == before - removed, "The reported count must match what left the buffer")

var quiet = [Float](repeating: 0, count: 1_000)
require(KokoroAudio.trimPadding(&quiet, chunkText: "hello", hasFollowingChunk: false) == 0,
        "Silent output must be left alone")

print("Kokoro text mapping, word timing, and trimming contracts passed")
