import Foundation
import AVFoundation

#if canImport(WhisperKit)
import WhisperKit

/// On-device speech-to-text.
///
/// Records while you hold the key, transcribes when you let go. No audio leaves
/// the machine, and no network call happens at any point — the model downloads
/// once from Hugging Face and is cached.
///
/// ## Push-to-talk, not always-listening
///
/// `docs/VOICE.md` chose this deliberately: a hotkey is a day's work and always
/// correct, where an always-listening wake word is weeks of work, misfires, and
/// means a hot microphone in your home.
///
/// It also makes **barge-in** trivial. Pressing the talk key stops her —
/// no acoustics involved. Interrupting a speaking assistant by voice alone
/// requires echo cancellation, because her own output through the speakers is
/// the loudest thing the microphone can hear; that is a real project, and this
/// sidesteps it entirely.
public final class WhisperTranscriber: TranscriptionEngine, @unchecked Sendable {

    /// Whisper is trained on 16 kHz mono. The microphone will not be, so every
    /// buffer is converted before it is kept.
    static let targetSampleRate = 16_000.0

    private let engine = AVAudioEngine()
    private var whisper: WhisperKit?
    private var samples: [Float] = []
    private var levelHandler: (@Sendable (Double) -> Void)?
    private let lock = NSLock()

    public private(set) var isListening = false

    /// `base.en` rather than `large-v3`.
    ///
    /// A push-to-talk utterance is a few seconds of clear, close-mic speech in
    /// one known language — the easiest case there is. `base.en` handles it in a
    /// fraction of the time and ~150 MB instead of ~1.5 GB, and that memory is
    /// contested: the language model, the TTS voice and the app are all resident
    /// at once during a spoken exchange.
    public var modelName = "base.en"

    public init() {}

    /// Load the model ahead of first use, so the first thing you say is not
    /// also the thing that waits for a download.
    public func prepare() async throws {
        guard whisper == nil else { return }
        do {
            whisper = try await WhisperKit(WhisperKitConfig(model: modelName))
        } catch {
            throw VoiceError.modelNotDownloaded(
                "\(modelName): \(error.localizedDescription)")
        }
    }

    // MARK: - Recording

    public func startListening(onLevel: @escaping @Sendable (Double) -> Void) async throws {
        guard !isListening else { return }
        try await prepare()

        lock.lock()
        samples.removeAll(keepingCapacity: true)
        levelHandler = onLevel
        lock.unlock()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false),
            let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        else {
            throw VoiceError.engineUnavailable("cannot convert microphone audio to 16 kHz mono")
        }

        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self,
                  let converted = Self.convert(buffer, using: converter, to: targetFormat)
            else { return }

            self.lock.lock()
            self.samples.append(contentsOf: Self.floats(of: converted))
            self.lock.unlock()

            if let level = Self.rms(of: converted) {
                self.levelHandler?(level)
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw VoiceError.microphonePermissionDenied
        }
        isListening = true
    }

    public func stopListening() async throws -> String {
        guard isListening else { return "" }
        teardown()

        lock.lock()
        let captured = samples
        samples.removeAll(keepingCapacity: true)
        lock.unlock()

        // Whisper hallucinates confidently on near-silence — a held key with
        // nothing said comes back as "Thank you." or a stray subtitle line.
        // Below a third of a second there is nothing worth transcribing.
        guard captured.count >= Int(Self.targetSampleRate * 0.3) else { return "" }

        guard let whisper else { throw VoiceError.engineUnavailable("model not loaded") }
        let results = try await whisper.transcribe(audioArray: captured)
        return results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func cancelListening() {
        guard isListening else { return }
        teardown()
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    private func teardown() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        isListening = false
        levelHandler?(0)
        levelHandler = nil
    }

    // MARK: - Audio helpers

    /// Resample a microphone buffer to Whisper's 16 kHz mono.
    ///
    /// The input node hands back the hardware's format — usually 44.1 or
    /// 48 kHz, often stereo. Feeding that to Whisper unconverted does not fail;
    /// it transcribes gibberish, which is worse.
    static func convert(_ buffer: AVAudioPCMBuffer,
                        using converter: AVAudioConverter,
                        to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }

        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? output : nil
    }

    static func floats(of buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    static func rms(of buffer: AVAudioPCMBuffer) -> Double? {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else {
            return nil
        }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += channel[i] * channel[i] }
        let rms = sqrt(sum / Float(n))
        guard rms > 0 else { return 0 }

        // Same decibel mapping as SystemVoice, for the same reason: speech RMS
        // sits in a narrow band and reads as almost nothing when mapped linearly.
        let db = 20 * log10(Double(rms))
        return min(1, max(0, (db - (-50)) / (-10 - (-50))))
    }
}
#endif

/// Used when WhisperKit is not linked or no model is installed.
///
/// Refuses with a reason rather than silently doing nothing. Typing to her
/// works regardless — speech is an input method, not the interface.
public final class UnavailableTranscriber: TranscriptionEngine, @unchecked Sendable {
    public let reason: String
    public var isListening: Bool { false }

    public init(reason: String = "Speech recognition is not available in this build.") {
        self.reason = reason
    }

    public func startListening(onLevel: @escaping @Sendable (Double) -> Void) async throws {
        throw VoiceError.engineUnavailable(reason)
    }

    public func stopListening() async throws -> String { "" }
    public func cancelListening() {}
}
