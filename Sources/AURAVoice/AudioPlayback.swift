import Foundation
import AVFoundation

/// Plays rendered audio and reports its amplitude while it plays.
///
/// Extracted from `SystemVoice` so `NeuralVoice` does not duplicate it. The
/// logic is short but the subtleties are the whole point:
///
/// - **The tap is on the playing node, not on rendering.** Both engines produce
///   audio faster than real time, so emitting levels as buffers are *made*
///   would run her mouth ahead of the sound and finish while she is still
///   audible.
/// - **1024 frames.** At 22–48 kHz that is 20–45 ms, a little faster than a
///   display frame. Larger buffers smear consonants into one long vowel.
/// - **Decibels, not raw RMS.** Speech RMS sits in a narrow band and a linear
///   mapping leaves the mouth barely open through normal speech.
final class AudioPlayback: @unchecked Sendable {

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var levelHandler: (@Sendable (Double) -> Void)?
    private var isTapped = false

    init() {
        engine.attach(player)
    }

    /// Play `buffers` to completion, reporting amplitude throughout.
    func play(_ buffers: [AVAudioPCMBuffer],
              onLevel: @escaping @Sendable (Double) -> Void) async throws {
        guard let format = buffers.first?.format else {
            onLevel(0)
            return
        }

        levelHandler = onLevel
        try start(format: format)

        scheduleAll(buffers)
        player.play()

        let duration = buffers.reduce(0.0) {
            $0 + Double($1.frameLength) / $1.format.sampleRate
        }
        try? await Task.sleep(for: .seconds(duration))

        stop()
        onLevel(0)
    }

    /// Play raw float samples — what a neural vocoder produces.
    func play(samples: [Float], sampleRate: Double,
              onLevel: @escaping @Sendable (Double) -> Void) async throws {
        guard !samples.isEmpty,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate, channels: 1,
                                         interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count))
        else {
            onLevel(0)
            return
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = buffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { source in
                channel.update(from: source.baseAddress!, count: samples.count)
            }
        }
        try await play([buffer], onLevel: onLevel)
    }

    func stop() {
        if player.isPlaying { player.stop() }
        removeTap()
        if engine.isRunning { engine.stop() }
        levelHandler?(0)
    }

    var isPlaying: Bool { player.isPlaying }

    /// Deliberately *not* `async`.
    ///
    /// The newest SDK adds an `async` `scheduleBuffer` overload whose default
    /// `completionCallbackType` is `.dataPlayedBack` — it suspends until that
    /// specific buffer has finished *playing*, not until it is merely
    /// enqueued. Swift prefers an async overload over a sync one, but only
    /// when the call site itself sits inside an `async` function; calling
    /// `scheduleBuffer` from `play(_:onLevel:)` directly resolved to the new
    /// overload. Awaiting it there would have been worse than a stutter: the
    /// original code schedules every buffer *before* calling `player.play()`,
    /// so the first `await` would hang forever waiting for playback that
    /// hasn't started yet. Even scheduled after `play()`, per-buffer
    /// completion awaiting serializes ~1024-frame buffers with an audible gap
    /// between each — a live, unresolved report on Apple's own developer
    /// forums (thread 817029). Isolating the loop in this ordinary
    /// synchronous method keeps the call site out of `async` context, so it
    /// resolves to the original fire-and-forget overload this file's design
    /// (gapless, schedule-then-play) depends on.
    private func scheduleAll(_ buffers: [AVAudioPCMBuffer]) {
        for buffer in buffers { player.scheduleBuffer(buffer, at: nil) }
    }

    // MARK: - Engine

    private func start(format: AVAudioFormat) throws {
        if engine.isRunning { engine.stop() }
        removeTap()

        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let level = Self.rms(of: buffer) else { return }
            self.levelHandler?(level)
        }
        isTapped = true

        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw VoiceError.engineUnavailable(error.localizedDescription)
        }
    }

    private func removeTap() {
        guard isTapped else { return }
        player.removeTap(onBus: 0)
        isTapped = false
    }

    /// Root mean square mapped to a 0...1 the mouth can use.
    static func rms(of buffer: AVAudioPCMBuffer) -> Double? {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else {
            return nil
        }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += channel[i] * channel[i] }
        let rms = sqrt(sum / Float(n))
        guard rms > 0 else { return 0 }

        // −50 dB is near-silence between words, −10 dB a loud vowel.
        let db = 20 * log10(Double(rms))
        return min(1, max(0, (db - (-50)) / (-10 - (-50))))
    }
}
