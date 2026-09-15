import Foundation
import Observation
import AURACore
import AURAAnalytics
import AURAIntelligence
import AURAVoice
import AURACharacter

/// The chat screen's state.
///
/// Holds the transcript, drives one exchange at a time, and routes each guarded
/// sentence to both the transcript and the voice — the same sentence, so what
/// she says and what she shows can never diverge.
@Observable
@MainActor
public final class ConversationViewModel {

    // MARK: Transcript

    public struct Turn: Identifiable, Equatable {
        public enum Speaker: Equatable { case you, aura }
        public let id = UUID()
        public let speaker: Speaker
        public var text: String
        /// Figures from the brief this turn actually quoted, deduplicated
        /// across its sentences.
        public var citations: [OutputGuard.Citation] = []
        public var isStreaming = false
    }

    public enum Status: Equatable {
        case idle
        case loadingModel
        case thinking
        /// She has begun speaking; generation may still be running.
        case answering
        case unavailable(String)
    }

    public private(set) var turns: [Turn] = []
    public private(set) var status: Status = .idle
    public private(set) var characterState: CharacterState = .idle
    /// Sentences the guard refused, kept for the session only. Never shown as
    /// her words — surfaced so a persistent problem is visible rather than
    /// looking like her trailing off.
    public private(set) var withheldCount = 0

    /// True while the talk key is held.
    public private(set) var isListening = false
    /// 0...1 from the microphone, so the UI can show it is hearing you.
    public private(set) var inputLevel: Double = 0
    /// Set when speech input fails — a denied microphone, a missing model.
    public private(set) var listeningError: String?

    public var draft = ""

    // MARK: Dependencies

    private let conversation: Conversation
    private let voice: any VoiceEngine
    private let transcriber: any TranscriptionEngine
    private let day: CalendarDay
    private var task: Task<Void, Never>?

    public init(model: any LanguageModel,
                briefBuilder: BriefBuilder,
                voice: any VoiceEngine,
                transcriber: any TranscriptionEngine,
                day: CalendarDay) {
        self.conversation = Conversation(model: model, briefBuilder: briefBuilder)
        self.voice = voice
        self.transcriber = transcriber
        self.day = day
        if !model.isReady, let unavailable = model as? UnavailableModel {
            self.status = .unavailable(unavailable.reason)
        }
    }

    // MARK: Asking

    public func send() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isBusy else { return }
        draft = ""
        ask(question)
    }

    public func ask(_ question: String) {
        turns.append(Turn(speaker: .you, text: question))
        turns.append(Turn(speaker: .aura, text: "", isStreaming: true))
        status = .thinking
        characterState = .thinking

        task = Task { [weak self] in
            guard let self else { return }
            await conversation.answer(question, about: day) { event in
                Task { @MainActor [weak self] in
                    self?.handle(event)
                }
            }
        }
    }

    // MARK: Push-to-talk

    /// Called when the talk key goes down.
    ///
    /// Interrupting her first is the barge-in: pressing the key to speak is an
    /// unambiguous signal that you want her to stop, and it needs no acoustics.
    /// Detecting interruption from the microphone alone would mean hearing past
    /// her own voice through the speakers, which is an echo-cancellation
    /// project, not a feature.
    public func startTalking() {
        guard !isListening else { return }
        if isBusy { interrupt() }
        listeningError = nil

        Task { [transcriber] in
            do {
                try await transcriber.startListening { level in
                    Task { @MainActor [weak self] in self?.inputLevel = level }
                }
                await MainActor.run { [weak self] in
                    self?.isListening = true
                    self?.characterState = .listening
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.listeningError = error.localizedDescription
                    self?.isListening = false
                    self?.characterState = .idle
                }
            }
        }
    }

    /// Called when the talk key comes up: transcribe and ask.
    public func stopTalking() {
        guard isListening else { return }
        isListening = false
        inputLevel = 0
        characterState = .thinking

        Task { [transcriber] in
            let text = (try? await transcriber.stopListening()) ?? ""
            await MainActor.run { [weak self] in
                guard let self else { return }
                let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !question.isEmpty else {
                    // A held key with nothing said is not an error, and not a
                    // question either. Say nothing and go back to idle.
                    self.characterState = .idle
                    return
                }
                self.ask(question)
            }
        }
    }

    /// Abandon a recording without asking anything.
    public func cancelTalking() {
        guard isListening else { return }
        transcriber.cancelListening()
        isListening = false
        inputLevel = 0
        characterState = .idle
    }

    /// Stop her immediately.
    ///
    /// Cuts generation and audio together. A companion that finishes its
    /// sentence over you is irritating within one conversation.
    public func interrupt() {
        task?.cancel()
        task = nil
        voice.stop()
        finishStreamingTurn()
        status = .idle
        characterState = .idle
    }

    public var isBusy: Bool {
        status == .thinking || status == .answering || status == .loadingModel
    }

    // MARK: Events

    private func handle(_ event: Conversation.Event) {
        switch event {
        case .sentence(let sentence, let citations):
            appendToCurrentTurn(sentence, citations: citations)
            status = .answering
            speak(sentence)

        case .withheld:
            // Deliberately not shown as her words, and deliberately not silent
            // either: a guard firing repeatedly is a real signal.
            withheldCount += 1

        case .finished:
            finishStreamingTurn()
            status = .idle

        case .failed(let message):
            finishStreamingTurn()
            status = .unavailable(message)
            characterState = .idle
        }
    }

    private func appendToCurrentTurn(_ sentence: String,
                                     citations: [OutputGuard.Citation]) {
        guard let index = turns.lastIndex(where: { $0.speaker == .aura && $0.isStreaming })
        else { return }
        turns[index].text += turns[index].text.isEmpty ? sentence : " " + sentence

        // Deduplicated across the whole turn: three sentences about sleep
        // produce one chip, not three.
        let existing = Set(turns[index].citations.map(\.metric))
        for citation in citations where !existing.contains(citation.metric) {
            turns[index].citations.append(citation)
        }
    }

    private func finishStreamingTurn() {
        guard let index = turns.lastIndex(where: { $0.speaker == .aura && $0.isStreaming })
        else { return }
        turns[index].isStreaming = false
        // An answer that produced nothing at all is removed rather than left as
        // an empty bubble.
        if turns[index].text.isEmpty { turns.remove(at: index) }
        characterState = .idle
    }

    private func speak(_ sentence: String) {
        Task { [voice] in
            try? await voice.speak(sentence) { level in
                Task { @MainActor [weak self] in
                    // The same amplitude that moves her mouth. One source, so
                    // the face and the audio cannot drift apart.
                    self?.characterState = .speaking(level: level)
                }
            }
            await MainActor.run { [weak self] in
                if self?.status != .thinking { self?.characterState = .idle }
            }
        }
    }
}
