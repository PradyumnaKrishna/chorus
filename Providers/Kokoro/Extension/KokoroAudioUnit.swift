import AVFoundation
import ChorusProviderKit
import os

// Speech synthesis audio units render offline rather than on the realtime audio
// thread, so allocating and locking inside the render block is safe here. This
// would not be acceptable in any other audio unit type.

private let log = Logger(subsystem: "in.onpy.Chorus.Kokoro", category: "AudioUnit")

/// Identifier of the downloadable model in this provider's `Provider.json`.
private let modelArtifactIdentifier = "kokoro-q8f16-model"

public final class KokoroAudioUnit: AVSpeechSynthesisProviderAudioUnit, @unchecked Sendable {

    private let outputBus: AUAudioUnitBus
    private var busArray: AUAudioUnitBusArray!

    // Built on first use: loading the model takes long enough that we don't want
    // it on the extension's launch path. `lazy var` cannot be used here -- it is
    // not atomic, and `engine` is reached from two threads at once: the system
    // calls `speechVoices` on its own thread while `render` runs on `work`. Two
    // callers would each load an 86 MB ONNX session and race on the stored value.
    private let engineLock = NSLock()
    private var loadedEngine: KokoroEngine?
    private var didLoadEngine = false

    private var engine: KokoroEngine? {
        engineLock.lock()
        defer { engineLock.unlock() }
        if !didLoadEngine {
            didLoadEngine = true
            loadedEngine = Self.makeEngine()
        }
        return loadedEngine
    }

    private static func makeEngine() -> KokoroEngine? {
        let bundle = Bundle(for: KokoroAudioUnit.self)
        guard let resources = bundle.resourceURL else { return nil }
        do {
            return try KokoroEngine(resources: resources, modelURL: installedModelURL(in: bundle))
        } catch {
            log.error("engine unavailable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// The downloaded model, or nil to fall back to whatever ships in the bundle.
    ///
    /// The location, expected size, and installed check all come from the same
    /// `Provider.json` the containing app installed against, so the extension
    /// cannot drift from what the installer actually wrote.
    private static func installedModelURL(in bundle: Bundle) -> URL? {
        do {
            let descriptor = try ProviderDescriptor.load(from: bundle)
            guard let artifact = descriptor.artifacts.first(where: {
                $0.identifier == modelArtifactIdentifier
            }) else {
                log.error("no artifact named \(modelArtifactIdentifier, privacy: .public)")
                return nil
            }
            let store = ArtifactStore(
                rootDirectory: try ProviderContainer.storageDirectory(in: bundle),
                artifacts: [artifact]
            )
            return store.isInstalled() ? store.destination(for: artifact) : nil
        } catch {
            log.error("model unavailable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private let work = DispatchQueue(label: "in.onpy.Chorus.Kokoro.synthesis", qos: .userInitiated)

    // Buffer shared between the synthesis queue and the render block.
    private let buffer = NSCondition()
    private var samples: [Float] = []
    private var readIndex = 0
    private var producing = false
    /// Bumped on every new or cancelled request so stale work is discarded.
    private var generation = 0

    @objc override init(componentDescription: AudioComponentDescription,
                        options: AudioComponentInstantiationOptions) throws {
        var description = AudioStreamBasicDescription(
            mSampleRate: KokoroEngine.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0)

        let format = AVAudioFormat(streamDescription: &description)!
        outputBus = try AUAudioUnitBus(format: format)
        try super.init(componentDescription: componentDescription, options: options)
        busArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
    }

    public override var outputBusses: AUAudioUnitBusArray { busArray }

    public override var channelCapabilities: [NSNumber] { [0, 1] }

    // MARK: - Voices

    public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
        get {
            (engine?.voices ?? []).map { voice in
                let provider = AVSpeechSynthesisProviderVoice(
                    name: voice.systemName,
                    identifier: voice.voiceIdentifier,
                    primaryLanguages: [voice.language.bcp47],
                    supportedLanguages: [voice.language.bcp47])
                provider.gender = voice.isFemale ? .female : .male
                provider.version = "1.0"
                return provider
            }
        }
        set { }
    }

    // MARK: - Requests

    public override func synthesizeSpeechRequest(_ speechRequest: AVSpeechSynthesisProviderRequest) {
        buffer.lock()
        generation += 1
        let generation = self.generation
        samples.removeAll(keepingCapacity: true)
        readIndex = 0
        producing = true
        buffer.unlock()

        work.async { [weak self] in
            self?.render(speechRequest, generation: generation)
        }
    }

    public override func cancelSpeechRequest() {
        buffer.lock()
        generation += 1
        samples.removeAll(keepingCapacity: true)
        readIndex = 0
        producing = false
        buffer.broadcast()
        buffer.unlock()
    }

    /// Synthesizes the request chunk by chunk, publishing audio and word
    /// markers as each chunk completes so playback can start early.
    private func render(_ request: AVSpeechSynthesisProviderRequest, generation: Int) {
        defer { finish(generation: generation) }

        guard let engine, let voice = engine.voice(withIdentifier: request.voice.identifier) else {
            log.error("no voice for \(request.voice.identifier, privacy: .public)")
            return
        }

        let ssml = SSMLText.parse(request.ssmlRepresentation)
        let characters = Array(ssml.text)
        var frames = 0

        for range in engine.chunkRanges(of: ssml.text) {
            guard isCurrent(generation) else { return }

            let text = String(characters[range])
            do {
                let audio = try engine.synthesize(text, voice: voice, speed: ssml.rate)
                guard isCurrent(generation) else { return }
                guard !audio.isEmpty else { continue }

                publishMarkers(for: range, in: ssml, characters: characters,
                               startFrame: frames, frameCount: audio.count, request: request)
                frames += audio.count
                append(audio, generation: generation)
            } catch {
                log.error("chunk failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        if ssml.trailingSilence > 0 {
            append([Float](repeating: 0, count: Int(ssml.trailingSilence * KokoroEngine.sampleRate)),
                   generation: generation)
        }
    }

    /// This ONNX integration exposes no phoneme durations, so word timings are apportioned
    /// across the chunk by character position. These remain approximate; clients
    /// requiring exact alignment should omit timed highlighting.
    private func publishMarkers(for range: Range<Int>, in ssml: SSMLText, characters: [Character],
                                startFrame: Int, frameCount: Int,
                                request: AVSpeechSynthesisProviderRequest) {
        guard let publish = speechSynthesisOutputMetadataBlock else { return }

        let markers = KokoroSpeechMarkers.words(text: String(characters[range]), characterOffset: range.lowerBound,
                                               ssml: ssml, startFrame: startFrame, frameCount: frameCount)

        guard !markers.isEmpty else { return }
        publish(markers, request)
    }

    // MARK: - Buffer plumbing

    private func isCurrent(_ generation: Int) -> Bool {
        buffer.lock(); defer { buffer.unlock() }
        return generation == self.generation
    }

    private func append(_ audio: [Float], generation: Int) {
        buffer.lock()
        if generation == self.generation { samples.append(contentsOf: audio) }
        buffer.broadcast()
        buffer.unlock()
    }

    private func finish(generation: Int) {
        buffer.lock()
        if generation == self.generation { producing = false }
        buffer.broadcast()
        buffer.unlock()
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        { [weak self] actionFlags, _, frameCount, _, outputAudioBufferList, _, _ in
            guard let self else { return kAudio_ParamError }

            let output = UnsafeMutableAudioBufferListPointer(outputAudioBufferList)[0]
            guard let raw = output.mData else { return kAudio_ParamError }
            let frames = raw.assumingMemoryBound(to: Float32.self)

            self.buffer.lock()

            // Wait for the synthesis queue to get ahead of playback. Safe
            // because this audio unit renders offline.
            while self.samples.count - self.readIndex < Int(frameCount) && self.producing {
                // Offline rendering must wait rather than insert unaccounted silence into marker timing.
                self.buffer.wait()
            }

            let available = max(0, self.samples.count - self.readIndex)
            let count = min(Int(frameCount), available)
            if count > 0 {
                self.samples.withUnsafeBufferPointer { source in
                    frames.update(from: source.baseAddress! + self.readIndex, count: count)
                }
                self.readIndex += count
            }
            for frame in count..<Int(frameCount) { frames[frame] = 0 }

            let complete = !self.producing && self.readIndex >= self.samples.count
            self.buffer.unlock()

            if complete {
                actionFlags.pointee = .offlineUnitRenderAction_Complete
            }
            return noErr
        }
    }
}
