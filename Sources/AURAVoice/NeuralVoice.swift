import Foundation
import AVFoundation

#if canImport(Kokoro)
import Kokoro

/// The voice that makes her a character rather than a screen reader.
///
/// Kokoro-82M, Apache 2.0, running locally. `docs/VOICE.md` calls this the
/// upgrade that actually matters: `SystemVoice` ships first so she can speak at
/// all, but it sounds like a system voice and always will.
///
/// ## Why this fits the memory budget when it looks like it should not
///
/// `docs/INTELLIGENCE.md` sizes this machine to the byte, and adding a second
/// model to a plan that already has a 14B LLM resident sounds reckless. It is
/// not, for two reasons:
///
/// - **82M parameters.** A few hundred megabytes, against the language model's
///   eight or nine gigabytes.
/// - **It runs on the Neural Engine, not the GPU.** The ANE is otherwise idle
///   while MLX holds the GPU, so the two barely contend. Roughly 100 ms to
///   synthesise a sentence, which is inside the voice budget with room to spare.
///
/// ## Why synthesis is per sentence
///
/// Not an optimisation — it falls out of the architecture. `SentenceStream`
/// already releases one guarded sentence at a time, so a sentence is exactly
/// what arrives here. Synthesising the whole response would mean waiting for
/// generation to finish, which is the thing the streaming design exists to
/// avoid.
public final class NeuralVoice: VoiceEngine, @unchecked Sendable {

    private let playback = AudioPlayback()
    private var pipeline: KPipeline?
    private let modelDirectory: URL

    public private(set) var isSpeaking = false

    /// Which of the 54 voices. Chosen once and kept — a companion whose voice
    /// changes between sessions is a different companion.
    public var voice = "af_heart"

    public var identifier: String { "Kokoro-82M · \(voice)" }

    public init(modelDirectory: URL) {
        self.modelDirectory = modelDirectory
    }

    /// Load the model and voice ahead of first use.
    public func prepare() async throws {
        guard pipeline == nil else { return }
        do {
            let model = try KModel(
                configURL: modelDirectory.appending(path: "config.json"),
                weightsURL: modelDirectory.appending(path: "kokoro-v1_0.safetensors"))
            let voices = VoiceLoader(
                baseDirectory: modelDirectory.appending(path: "voices"),
                enableDownload: true)
            pipeline = KPipeline(model: model, voices: voices)
        } catch {
            throw VoiceError.modelNotDownloaded(
                "Kokoro: \(error.localizedDescription)")
        }
    }

    public func speak(_ text: String,
                      onLevel: @escaping @Sendable (Double) -> Void) async throws {
        stop()
        try await prepare()
        guard let pipeline else { throw VoiceError.engineUnavailable("pipeline not loaded") }

        isSpeaking = true
        defer { isSpeaking = false }

        let result = try pipeline.synthesize(text: text, voice: voice)
        try Task.checkCancellation()
        try await playback.play(samples: result.audio, sampleRate: 24_000,
                                onLevel: onLevel)
    }

    public func stop() {
        // Cut, never fade — the same contract as every other engine.
        playback.stop()
        isSpeaking = false
    }
}
#endif
