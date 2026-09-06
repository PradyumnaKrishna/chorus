import AVFoundation

/// The provider API measures time in PCM bytes and text in source-SSML UTF-16 units.
/// Kokoro has no phoneme alignment, so positions within a chunk remain estimates.
enum KokoroSpeechMarkers {
    static func words(text: String, characterOffset: Int, ssml: SSMLText,
                      startFrame: Int, frameCount: Int) -> [AVSpeechSynthesisMarker] {
        let length = max(text.count, 1)
        var markers: [AVSpeechSynthesisMarker] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .localized]) { _, range, _, _ in
            let offset = text.distance(from: text.startIndex, to: range.lowerBound)
            let end = text.distance(from: text.startIndex, to: range.upperBound)
            let frame = startFrame + Int(Double(frameCount) * Double(offset) / Double(length))
            let sourceRange = ssml.ssmlRange(for: (characterOffset + offset)..<(characterOffset + end))
            markers.append(AVSpeechSynthesisMarker(markerType: .word, forTextRange: sourceRange,
                                                   atByteSampleOffset: frame * MemoryLayout<Float>.stride))
        }
        return markers
    }
}
