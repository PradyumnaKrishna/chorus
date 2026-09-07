import Foundation

enum KokoroAudio {
    /// Removes padding from 24 kHz mono model output. Keep 40 ms
    /// before a quiet onset; a louder threshold mistakes soft consonants for silence.
    /// Leave silent output and onsets beyond the first half-second unchanged.
    /// At artificial word splits, retain 80 ms of the trailing padding; preserve
    /// the model's pause at punctuation and at the end of the request.
    static func trimPadding(_ samples: inout [Float], chunkText: String, hasFollowingChunk: Bool) {
        if let onset = samples.prefix(12_000).firstIndex(where: { abs($0) >= 0.001 }) {
            samples.removeFirst(max(0, onset - 960))
        }
        guard hasFollowingChunk, let last = chunkText.last(where: { !$0.isWhitespace }),
              last.isLetter || last.isNumber,
              let ending = samples.suffix(24_000).lastIndex(where: { abs($0) >= 0.001 }) else { return }
        samples.removeLast(max(0, samples.count - ending - 1 - 1_920))
    }
}
