import Foundation

/// Text-to-speech, behind a protocol because the right engine is a taste
/// decision that should not be baked into the app.
///
/// Three conformers are planned, in this order (docs/VOICE.md):
///
///   1. `SystemVoice`  -- AVSpeechSynthesizer. Free, offline, zero setup,
///      ships in M3 so she can talk on day one. Sounds like a system voice.
///   2. `NeuralVoice`  -- a local neural model (Kokoro / Piper class) running
///      on the Neural Engine. Still fully offline, dramatically warmer, and
///      the one that makes her feel like a character rather than a screen
///      reader.
///   3. `RemoteVoice`  -- a hosted API. Best quality, but it sends text off
///      the machine, so it is opt-in, off by default, and never the fallback.
///
/// Everything above the protocol is identical in all three cases.
public protocol VoiceEngine: AnyObject, Sendable {
    /// Speak, and stream back a 0...1 amplitude at display rate so the
    /// character's mouth and glow can track the actual audio. Without this the
    /// mouth flaps on a timer and the illusion collapses immediately.
    func speak(_ text: String, onLevel: @escaping @Sendable (Double) -> Void) async throws

    func stop()

    var isSpeaking: Bool { get }
}

/// Speech-to-text, so she can be talked to rather than only typed at.
///
/// Planned conformer is WhisperKit -- Whisper compiled to Core ML, running on
/// the Neural Engine. Fully on-device: no audio leaves the machine.
public protocol TranscriptionEngine: AnyObject, Sendable {
    func startListening(onPartial: @escaping @Sendable (String) -> Void) async throws
    func stopListening() async throws -> String
    var isListening: Bool { get }
}

public enum VoiceError: Error, Sendable {
    case engineUnavailable(String)
    case microphonePermissionDenied
    case modelNotDownloaded(String)
}
