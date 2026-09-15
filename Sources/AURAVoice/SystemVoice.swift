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
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    private var levelHandler: (@Sendable (Double) -> Void)?
    private var isTapped = false

    public private(set) var isSpeaking = false

    /// Which system voice. Chosen once and kept: a companion whose voice changes
    /// between sessions is a different companion.
    public var voiceIdentifier: String?

    /// 0...1, where 0.5 is the system default rate.
    public var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    public override init() {
        super.init()
        engine.attach(player)
    }

    public func speak(_ text: String,
                      onLevel: @escaping @Sendable (Double) -> Void) async throws {
        stop()

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        if let id = voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = voice
        }

        levelHandler = onLevel
        isSpeaking = true
        defer { isSpeaking = false }

        var buffers: [AVAudioPCMBuffer] = []

        // Render first, play second. Collecting the buffers lets the engine be
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

        guard let format = buffers.first?.format else {
            onLevel(0)
            return
        }

        try startEngine(format: format)

        for buffer in buffers {
            player.scheduleBuffer(buffer, at: nil)
        }

        player.play()

        // Wait for playback rather than for rendering. The buffers were ready
        // long before this point.
        let duration = buffers.reduce(0.0) {
            $0 + Double($1.frameLength) / $1.format.sampleRate
        }
        try? await Task.sleep(for: .seconds(duration))

        stop()
        onLevel(0)
    }

    public func stop() {
        // Cut, never fade. She must stop the moment you start talking, and a
        // companion that politely finishes its sentence over you is immediately
        // irritating.
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        if player.isPlaying { player.stop() }
        removeTap()
        if engine.isRunning { engine.stop() }
        levelHandler?(0)
        isSpeaking = false
    }

    // MARK: - Engine and tap

    private func startEngine(format: AVAudioFormat) throws {
        if engine.isRunning { engine.stop() }
        removeTap()

        engine.connect(player, to: engine.mainMixerNode, format: format)
        installTap(format: format)

        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw VoiceError.engineUnavailable(error.localizedDescription)
        }
    }

    private func installTap(format: AVAudioFormat) {
        // 1024 frames at 22–48 kHz lands between 20 and 45 ms — a little faster
        // than a display frame, which is what a mouth needs. Larger buffers
        // smear consonants into one long vowel.
        player.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let level = Self.rms(of: buffer) else { return }
            self.levelHandler?(level)
        }
        isTapped = true
    }

    private func removeTap() {
        guard isTapped else { return }
        player.removeTap(onBus: 0)
        isTapped = false
    }

    /// Root mean square of a buffer, mapped to a 0...1 the mouth can use.
    ///
    /// Speech RMS is small and lives in a narrow band, so a linear mapping leaves
    /// the mouth barely open through normal speech. Converting to decibels and
    /// normalising over a speech-shaped floor gives a range that actually reads
    /// as talking.
    static func rms(of buffer: AVAudioPCMBuffer) -> Double? {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else {
            return nil
        }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += channel[i] * channel[i] }
        let rms = sqrt(sum / Float(n))

        guard rms > 0 else { return 0 }
        let db = 20 * log10(Double(rms))

        // −50 dB is near-silence between words, −10 dB is a loud vowel.
        let floor = -50.0, ceiling = -10.0
        return min(1, max(0, (db - floor) / (ceiling - floor)))
    }
}
