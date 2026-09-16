import Foundation
import AVFoundation

/// Text-to-speech using the system synthesiser.
///
/// Free, offline, no download, available from the first build — which is the
/// point. It sounds like a system voice and will not on its own make her feel
/// like a character, but having her *speak* early is what tells you whether the
/// rest of the illusion works. `NeuralVoice` replaces it later without anything
/// above this protocol changing.
///
/// ## Why this is more than a call to `speak(_:)`
///
/// The one-line version — `AVSpeechSynthesizer.speak(utterance)` — plays audio
/// and tells you nothing about it. A mouth animated against that has to guess,
/// which means a timer, and a mouth on a timer reads as a cartoon playing over
/// audio rather than as someone talking.
///
/// So instead this renders to buffers with `write(_:toBufferCallback:)`, plays
/// them through an `AVAudioEngine`, and taps the output to emit a real
/// amplitude at display rate. The mouth then tracks the actual waveform.
///
/// The subtlety worth knowing: `write` produces buffers **faster than
/// real time**. Emitting levels as they arrive would run the mouth ahead of the
/// sound and finish before she stopped talking. The tap is on the playing node,
/// so levels are emitted in step with what is actually audible.
public final class SystemVoice: NSObject, VoiceEngine, @unchecked Sendable {

    private let synthesizer = AVSpeechSynthesizer()
    private let playback = AudioPlayback()

    public private(set) var isSpeaking = false

    /// Which system voice. Chosen once and kept: a companion whose voice
    /// changes between sessions is a different companion.
    public var voiceIdentifier: String?

    /// 0...1, where 0.5 is the system default rate.
    public var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    public var identifier: String {
        guard let voiceIdentifier,
              let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier)
        else { return "System voice" }
        return "System voice · \(voice.name)"
    }

    public override init() {
        super.init()
    }

    public func speak(_ text: String,
                      onLevel: @escaping @Sendable (Double) -> Void) async throws {
        stop()

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        if let id = voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = voice
        }

        isSpeaking = true
        defer { isSpeaking = false }

        var buffers: [AVAudioPCMBuffer] = []

        // Render first, play second. Collecting the buffers lets playback be
        // configured for the exact format the synthesiser produced, rather than
        // guessing one up front and resampling.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var finished = false
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                // A zero-length buffer is the synthesiser's end-of-stream marker.
                if pcm.frameLength == 0 {
                    if !finished { finished = true; continuation.resume() }
                    return
                }
                buffers.append(pcm)
            }
        }

        try Task.checkCancellation()
        try await playback.play(buffers, onLevel: onLevel)
    }

    public func stop() {
        // Cut, never fade. She must stop the moment you start talking, and a
        // companion that politely finishes its sentence over you is immediately
        // irritating.
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        playback.stop()
        isSpeaking = false
    }
}
