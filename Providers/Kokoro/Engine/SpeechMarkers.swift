import AVFoundation

/// The provider API measures time in PCM bytes and text in source-SSML UTF-16 units.
enum KokoroSpeechMarkers {
    /// Word markers for one synthesized chunk.
    ///
    /// `timings` are offsets into the untrimmed audio; `trimmedLeadingSamples` moves
    /// them onto the buffer actually published. A word trimmed away entirely is
    /// dropped rather than pinned to the start of the chunk.
    static func words(_ timings: [WordTiming], characterOffset: Int, ssml: SSMLText,
                      startFrame: Int, trimmedLeadingSamples: Int,
                      sampleCount: Int) -> [AVSpeechSynthesisMarker] {
        timings.compactMap { timing in
            let offset = timing.samples.lowerBound - trimmedLeadingSamples
            guard offset < sampleCount else { return nil }
            let range = ssml.ssmlRange(for: (characterOffset + timing.source.lowerBound)
                                        ..< (characterOffset + timing.source.upperBound))
            guard range.length > 0 else { return nil }
            return AVSpeechSynthesisMarker(
                markerType: .word,
                forTextRange: range,
                atByteSampleOffset: (startFrame + max(0, offset)) * MemoryLayout<Float>.stride)
        }
    }
}
