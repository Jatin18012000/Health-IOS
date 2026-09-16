import Foundation

/// Text-to-speech, behind a protocol because the right engine is a taste
/// decision that should not be baked into the app.
///
/// Three conformers are planned, in this order (docs/VOICE.md):
///
///   1. `SystemVoice`  -- AVSpeechSynthesizer. Free, offline, zero setup.
///      Implemented. Sounds like a system voice, which is the point: having her
///      speak early is what tells you whether the rest of the illusion works.
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

    /// Stop immediately, cutting the audio rather than fading it.
    ///
    /// She must stop the moment you start talking. A companion that politely
    /// finishes its sentence over you is irritating within one conversation.
    func stop()

    var isSpeaking: Bool { get }
}

/// Speech-to-text, so she can be talked to rather than only typed at.
///
/// WhisperKit — Whisper compiled to Core ML, running on the Neural Engine.
/// Fully on-device; no audio leaves the machine.
///
/// ## Why this reports a level rather than partial text
///
/// The protocol originally promised `onPartial: (String) -> Void`, streaming
/// interim transcriptions as you spoke. WhisperKit's open-source surface does
/// not do that: true low-latency streaming lives in Argmax's paid tier, and the
/// free package transcribes a **complete** buffer. Faking partials by
/// re-transcribing a growing buffer several times a second would burn the
/// Neural Engine the language model needs and still be wrong until you stopped.
///
/// So the contract says what is actually true: while you hold the key, the
/// engine reports how loudly it is hearing you — enough for the UI to show it
/// is listening — and the text arrives when you let go. For push-to-talk, which
/// is what `docs/VOICE.md` specifies, that is the whole interaction anyway.
public protocol TranscriptionEngine: AnyObject, Sendable {
    /// Begin recording. `onLevel` fires at display rate with a 0...1 amplitude
    /// so the UI can show it is hearing you.
    func startListening(onLevel: @escaping @Sendable (Double) -> Void) async throws

    /// Stop recording and transcribe what was captured.
    func stopListening() async throws -> String

    /// Abandon a recording without transcribing it.
    func cancelListening()

    /// Load the model ahead of first use. Default no-op.
    ///
    /// On the protocol rather than the conformer so the app never has to
    /// downcast to find out whether warming up is possible.
    func prepare() async throws

    var isListening: Bool { get }
}

public extension TranscriptionEngine {
    func prepare() async throws {}
}

/// Builds the engines available in this build.
///
/// The `canImport` checks belong here, in the module that actually depends on
/// WhisperKit — the app target links `AURAVoice`, not WhisperKit, so the same
/// conditional written up there is always false.
public enum VoiceFactory {

    /// The best voice this build and this machine can manage.
    ///
    /// Neural when its weights are present, the system voice otherwise. The app
    /// never learns which it got — that is the point of the protocol, and it
    /// means installing the weights later upgrades her without a code change.
    public static func speech(modelDirectory: URL? = nil) -> any VoiceEngine {
        #if canImport(Kokoro)
        if let modelDirectory,
           FileManager.default.fileExists(
               atPath: modelDirectory.appending(path: "config.json").path) {
            return NeuralVoice(modelDirectory: modelDirectory)
        }
        #endif
        return SystemVoice()
    }

    public static func transcription() -> any TranscriptionEngine {
        #if canImport(WhisperKit)
        return WhisperTranscriber()
        #else
        return UnavailableTranscriber(
            reason: "Speech recognition is not available in this build, so talking to her "
                  + "is off. Typing works normally.")
        #endif
    }
}

public enum VoiceError: Error, Sendable {
    case engineUnavailable(String)
    case microphonePermissionDenied
    case modelNotDownloaded(String)
}
