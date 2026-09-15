import Foundation
import AURACore
import AURAMemory

/// Keeps memory bounded and proposes what is worth remembering.
///
/// Two jobs, both of which use the language model for what it is actually good
/// at — reading prose and writing prose — and neither of which lets it decide
/// anything on its own.
public actor MemoryKeeper {

    private let model: any LanguageModel
    private let memory: MemoryStore

    /// Conversations older than this are compressed.
    ///
    /// A day, not an hour: coming back to something the same evening should
    /// find it verbatim, because that is when the detail still matters.
    public var summariseAfter: TimeInterval = 24 * 60 * 60

    public init(model: any LanguageModel, memory: MemoryStore) {
        self.model = model
        self.memory = memory
    }

    // MARK: - Summarising

    /// Compress old conversations so context stays bounded.
    ///
    /// Run on a schedule rather than after every exchange: summarising costs a
    /// generation, and doing it while she is mid-conversation takes the GPU she
    /// needs to answer.
    public func summariseOldConversations(limit: Int = 3) async {
        let cutoff = Date().addingTimeInterval(-summariseAfter)
        guard let stale = try? await memory.conversationsAwaitingSummary(olderThan: cutoff)
        else { return }

        for conversation in stale.prefix(limit) {
            guard let turns = try? await memory.turns(in: conversation.id),
                  !turns.isEmpty else { continue }

            let transcript = turns.map {
                "\($0.speaker == .you ? "Them" : "You"): \($0.text)"
            }.joined(separator: "\n")

            guard let summary = try? await model.complete(
                system: Self.summarySystem, user: transcript, onToken: { _ in })
            else { continue }

            let cleaned = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            try? await memory.setSummary(cleaned, for: conversation.id)
        }
    }

    static let summarySystem = """
        Summarise this conversation in two or three sentences, from your own \
        point of view, as something you would recall weeks later.

        Keep what would still matter then: what they asked about, anything they \
        told you about their life, and what you concluded. Drop the numbers — \
        those are re-read from their data, not remembered. Write plainly, no \
        preamble.
        """

    // MARK: - Proposing facts

    /// Read a finished conversation for things worth remembering.
    ///
    /// Everything this produces is a **proposal**. Nothing reaches a brief
    /// until you confirm it, which is the point: a companion that quietly
    /// accumulates conclusions about you is unsettling, and one that asks is
    /// not. It is also the safeguard against the model's own inference —
    /// "they mentioned being tired" becoming "they have a sleep disorder".
    public func proposeFacts(from conversationID: UUID) async -> Int {
        guard let turns = try? await memory.turns(in: conversationID) else { return 0 }
        let yours = turns.filter { $0.speaker == .you }
        // Only what THEY said. Extracting facts from her own output would let
        // her cite her own guesses back as things you told her.
        guard !yours.isEmpty else { return 0 }

        let transcript = yours.map(\.text).joined(separator: "\n")
        guard let raw = try? await model.complete(
            system: Self.extractionSystem, user: transcript, onToken: { _ in })
        else { return 0 }

        var proposed = 0
        for candidate in Self.parse(raw) {
            let fact = Fact(text: candidate.text, kind: candidate.kind,
                            status: .proposed, sourceQuote: candidate.quote)
            if (try? await memory.propose(fact)) == true { proposed += 1 }
        }
        return proposed
    }

    static let extractionSystem = """
        Read what this person said and list anything about their life that would \
        still be useful to know in a month — a goal, an injury, a trip, a \
        constraint, a preference about how you talk to them.

        One per line, in this exact format:

        KIND | the fact in your own words, under 12 words | the phrase they used

        KIND is one of: context, condition, preference, life.

        Rules:
        - Only what they actually said. Do not infer, diagnose, or extrapolate.
        - Nothing about a single day — that is in their data already.
        - If there is nothing worth keeping, write NOTHING and stop.
        """

    struct Candidate {
        let kind: Fact.Kind
        let text: String
        let quote: String?
    }

    /// Parse the model's lines, discarding anything that does not fit.
    ///
    /// Strict on purpose. A malformed line is dropped rather than salvaged:
    /// these become things she believes about you, so a half-parsed fact is
    /// worse than a missing one.
    ///
    /// (Apple's Foundation Models framework would make this structurally
    /// impossible to get wrong via `@Generable` — see `docs/INTELLIGENCE.md`.
    /// Worth moving here once the extraction path is exercised.)
    static func parse(_ raw: String) -> [Candidate] {
        raw.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 2)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2,
                  let kind = Fact.Kind(rawValue: parts[0].lowercased()),
                  !parts[1].isEmpty,
                  parts[1].count <= 120
            else { return nil }
            return Candidate(kind: kind, text: parts[1],
                             quote: parts.count > 2 ? parts[2] : nil)
        }
    }
}
