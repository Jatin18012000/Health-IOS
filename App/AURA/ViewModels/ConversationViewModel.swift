import Foundation
import Observation
import AURACore
import AURAAnalytics
import AURAIntelligence
import AURAMemory
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

    /// Where the transcript is written, and what reads it afterwards.
    ///
    /// Both optional: memory failing to open must not take the conversation
    /// with it. Without them she still answers — she just does not remember
    /// having done so.
    private let memory: MemoryStore?
    private let keeper: MemoryKeeper?
    /// Created on the first turn, not on the first appearance of the screen.
    /// Opening the Companion tab and closing it again is not a conversation,
    /// and a store full of empty ones makes `recentConversations` useless.
    private var storedConversationID: UUID?
    /// The one task that creates the conversation row. See `record`.
    private var conversationSetup: Task<UUID?, Never>?
    /// Tail of the chain of transcript writes, so they land in order.
    private var pendingWrite: Task<Void, Never>?

    public init(model: any LanguageModel,
                briefBuilder: BriefBuilder,
                voice: any VoiceEngine,
                transcriber: any TranscriptionEngine,
                day: CalendarDay,
                memory: MemoryStore? = nil,
                keeper: MemoryKeeper? = nil) {
        self.conversation = Conversation(model: model, briefBuilder: briefBuilder)
        self.voice = voice
        self.transcriber = transcriber
        self.day = day
        self.memory = memory
        self.keeper = keeper
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
        record(.you, question)

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
        if turns[index].text.isEmpty {
            turns.remove(at: index)
        } else {
            // Recorded only once it is finished. Storing it sentence by
            // sentence would leave a half-answer in memory if she is
            // interrupted, and a half-answer is a thing she never actually
            // said.
            record(.aura, turns[index].text)
        }
        characterState = .idle
    }

    // MARK: Memory

    /// Append one turn to the stored transcript, starting a conversation row if
    /// this is the first.
    private func record(_ speaker: StoredTurn.Speaker, _ text: String) {
        guard let memory else { return }

        // The conversation row is created exactly once, by a task stored
        // synchronously here and awaited by every later turn. Checking for an
        // existing id and then awaiting the insert would let two turns recorded
        // in quick succession each find none and start one, splitting the
        // transcript across two conversations.
        let setup: Task<UUID?, Never>
        if let existing = conversationSetup {
            setup = existing
        } else {
            setup = Task { try? await memory.startConversation().id }
            conversationSetup = setup
        }

        // Stamped now, not when the write lands: `turns(in:)` orders by this.
        let at = Date()

        // Chained, so the writes are serial and `endConversation` has one thing
        // to wait on. Without the chain, proposing facts could read a
        // transcript whose last turn had not landed yet.
        let previous = pendingWrite
        pendingWrite = Task {
            await previous?.value
            guard let id = await setup.value else { return }
            storedConversationID = id
            try? await memory.append(StoredTurn(
                conversationID: id, speaker: speaker, text: text, at: at))
        }
    }

    /// Close the current conversation and read it for things worth remembering.
    ///
    /// Everything this produces is a **proposal** waiting in the Memory screen.
    /// Nothing reaches a brief until it is confirmed there, which is the point:
    /// a companion that quietly accumulates conclusions about you is
    /// unsettling, and one that asks is not.
    public func endConversation() async {
        // Awaited rather than read straight off `storedConversationID`: the
        // last turn's write may still be in flight, and proposing facts from a
        // transcript missing its final turn is worse than waiting a moment.
        await pendingWrite?.value
        let id = await conversationSetup?.value
        pendingWrite = nil
        conversationSetup = nil
        storedConversationID = nil
        turns.removeAll()
        withheldCount = 0
        guard let id else { return }
        _ = await keeper?.proposeFacts(from: id)
    }

    /// True when there is a conversation worth closing.
    public var hasTranscript: Bool { !turns.isEmpty }

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
