import Foundation

/// Where one source word falls in the audio synthesized for it.
struct WordTiming: Equatable {
    /// Character offsets into the text that was synthesized.
    let source: Range<Int>
    /// Sample offsets into the audio produced for that text.
    let samples: Range<Int>
}

/// Turns the model's per-token frame durations into sample positions.
enum SpeechAlignment {

    /// Sample spans for the unpadded tokens of one forward pass.
    ///
    /// Kokoro reports one frame count per *padded* id. The reference pipeline runs
    /// at 600 samples per frame, but deriving that scale from this pass instead of
    /// assuming it keeps offsets exact under any speed setting or future export.
    static func spans(frames: [Float], totalSamples: Int) -> [Range<Int>] {
        guard frames.count > 2, totalSamples > 0 else { return [] }
        let total = frames.reduce(Float(0)) { $0 + max(0, $1) }
        guard total > 0 else { return [] }
        let scale = Double(totalSamples) / Double(total)

        // Accumulate before rounding, so the error cannot compound across a passage.
        var elapsed = Double(max(0, frames[0])) * scale
        var start = min(totalSamples, Int(elapsed.rounded()))
        var spans: [Range<Int>] = []
        spans.reserveCapacity(frames.count - 2)
        for frame in frames[1 ..< frames.count - 1] {
            elapsed += Double(max(0, frame)) * scale
            let end = min(totalSamples, max(start, Int(elapsed.rounded())))
            spans.append(start ..< end)
            start = end
        }
        return spans
    }

    /// Folds per-token spans into one span per source word, merging neighbours that
    /// name the same source: espeak turns some words into several phonetic ones, and
    /// the reader should see the word highlighted once.
    static func timings(for words: [MappedText.Run], spans: [Range<Int>]) -> [WordTiming] {
        var timings: [WordTiming] = []
        for word in words {
            let tokens = word.tokens.clamped(to: spans.startIndex ..< spans.endIndex)
            guard !tokens.isEmpty else { continue }
            let samples = spans[tokens.lowerBound].lowerBound ..< spans[tokens.upperBound - 1].upperBound
            if let previous = timings.last, previous.source == word.source {
                timings[timings.count - 1] = WordTiming(
                    source: word.source, samples: previous.samples.lowerBound ..< samples.upperBound)
            } else {
                timings.append(WordTiming(source: word.source, samples: samples))
            }
        }
        return timings
    }
}
