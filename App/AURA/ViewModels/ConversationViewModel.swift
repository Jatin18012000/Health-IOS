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
        /// Figures from the brief that this turn actually quoted.
        public var citations: [Citation] = []
        public var isStreaming = false
    }

    public struct Citation: Identifiable, Equatable {
        public let id = UUID()
        public let value: String
        public let source: String
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

    public var draft = ""

    // MARK: Dependencies

    private let conversation: Conversation
    private let voice: any VoiceEngine
    private let day: CalendarDay
    private var task: Task<Void, Never>?

    public init(model: any LanguageModel,
                briefBuilder: BriefBuilder,
                voice: any VoiceEngine,
                day: CalendarDay) {
        self.conversation = Conversation(model: model, briefBuilder: briefBuilder)
        self.voice = voice
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
        case .sentence(let sentence):
            appendToCurrentTurn(sentence)
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

    private func appendToCurrentTurn(_ sentence: String) {
        guard let index = turns.lastIndex(where: { $0.speaker == .aura && $0.isStreaming })
        else { return }
        turns[index].text += turns[index].text.isEmpty ? sentence : " " + sentence
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
