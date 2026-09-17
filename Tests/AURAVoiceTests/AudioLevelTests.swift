import Testing
import Foundation
import AVFoundation
@testable import AURAVoice

/// The amplitude mapping that drives her mouth.
///
/// `docs/CHARACTER.md` ranks a mouth tracking real audio amplitude as the
/// single highest-leverage detail in the whole project — above art quality,
/// above resolution, above the number of poses. This function is that mapping,
/// and it is four lines of arithmetic nothing else covers.
///
/// Every expectation is derived from the dB scale in the source, not copied
/// from a run: the window is −50 dB (near-silence between words) to −10 dB (a
/// loud vowel), mapped onto 0...1 and clamped at both ends.
@Suite("Audio level")
struct AudioLevelTests {

    /// A buffer of constant amplitude. RMS of a constant signal is the constant
    /// itself, which is what makes the decibel arithmetic below checkable by
    /// hand rather than by running it.
    private static func buffer(amplitude: Float, frames: Int = 1024) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: 48_000, channels: 1,
                                   interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                      frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        let channel = buffer.floatChannelData![0]
        for i in 0..<frames { channel[i] = amplitude }
        return buffer
    }

    /// Amplitude whose RMS is exactly `db` decibels.
    private static func amplitude(forDecibels db: Double) -> Float {
        Float(pow(10, db / 20))
    }

    private static func isClose(_ a: Double, _ b: Double,
                               within tolerance: Double = 0.01) -> Bool {
        abs(a - b) < tolerance
    }

    @Test("−30 dB sits exactly halfway up the range")
    func midpoint() throws {
        let level = try #require(AudioPlayback.rms(of: Self.buffer(
            amplitude: Self.amplitude(forDecibels: -30))))
        // (−30 − (−50)) / (−10 − (−50)) = 20 / 40.
        #expect(Self.isClose(level, 0.5))
    }

    @Test("the quiet end of the window maps to a closed mouth")
    func floor() throws {
        let level = try #require(AudioPlayback.rms(of: Self.buffer(
            amplitude: Self.amplitude(forDecibels: -50))))
        #expect(Self.isClose(level, 0))
    }

    @Test("the loud end of the window maps to a fully open mouth")
    func ceiling() throws {
        let level = try #require(AudioPlayback.rms(of: Self.buffer(
            amplitude: Self.amplitude(forDecibels: -10))))
        #expect(Self.isClose(level, 1))
    }

    @Test("anything outside the window is clamped, never negative or over one")
    func clamping() throws {
        // Quieter than the floor. An unclamped value here would be negative,
        // and a negative mouth opening is a rendering artefact, not a face.
        let tooQuiet = try #require(AudioPlayback.rms(of: Self.buffer(
            amplitude: Self.amplitude(forDecibels: -70))))
        #expect(tooQuiet == 0)

        // Louder than the ceiling: full scale is 0 dB, which the raw formula
        // would map to 1.25.
        let tooLoud = try #require(AudioPlayback.rms(of: Self.buffer(amplitude: 1.0)))
        #expect(tooLoud == 1)
    }

    @Test("digital silence is zero, not negative infinity")
    func silence() throws {
        // log10(0) is −inf, so this has to be caught before the arithmetic.
        // Left uncaught it propagates a NaN into the mouth and the face freezes.
        let level = try #require(AudioPlayback.rms(of: Self.buffer(amplitude: 0)))
        #expect(level == 0)
        #expect(!level.isNaN)
    }

    @Test("an empty buffer has no level at all")
    func emptyBuffer() {
        let empty = Self.buffer(amplitude: 0.5, frames: 1024)
        empty.frameLength = 0
        // Nil rather than zero: no audio arrived, which is different from audio
        // that arrived silent. The caller leaves the mouth where it was.
        #expect(AudioPlayback.rms(of: empty) == nil)
    }

    @Test("louder audio always produces a higher level")
    func monotonic() throws {
        var previous = -1.0
        for db in stride(from: -50.0, through: -10.0, by: 5.0) {
            let level = try #require(AudioPlayback.rms(of: Self.buffer(
                amplitude: Self.amplitude(forDecibels: db))))
            #expect(level > previous)
            previous = level
        }
    }
}

/// The voice the app actually gets, and what it calls itself.
@Suite("Voice selection")
struct VoiceFactoryTests {

    @Test("without neural weights the system voice is chosen")
    func fallsBackToSystemVoice() {
        // The app must never learn which it got — that is the point of the
        // protocol, and it is what makes installing the weights later a
        // zero-code upgrade. `identifier` is display-only for that reason.
        let voice = VoiceFactory.speech(modelDirectory: nil)
        #expect(voice is SystemVoice)
        #expect(!voice.isSpeaking)
    }

    @Test("a directory without a config is not mistaken for installed weights")
    func emptyDirectoryIsNotWeights() throws {
        let empty = FileManager.default.temporaryDirectory
            .appending(path: "aura-voice-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }

        #expect(VoiceFactory.speech(modelDirectory: empty) is SystemVoice)
    }

    @Test("the system voice names itself even with no voice chosen")
    func systemVoiceIdentifier() {
        let voice = SystemVoice()
        #expect(voice.identifier == "System voice")

        // An identifier that does not resolve must fall back rather than
        // produce "System voice · " with nothing after it.
        voice.voiceIdentifier = "not.a.real.voice.identifier"
        #expect(voice.identifier == "System voice")
    }
}
