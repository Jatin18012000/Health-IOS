import Foundation

/// Releases a streamed response one complete sentence at a time, checking each
/// against `OutputGuard` before anyone sees or hears it.
///
/// ## The problem this solves
///
/// Two requirements in this project are in direct tension:
///
/// - `docs/VOICE.md`: she must **start speaking before generation finishes**.
///   The budget from you stopping to her starting is about 1.5 seconds, and
///   waiting for a complete response blows it on its own.
/// - `docs/INTELLIGENCE.md`: **nothing is spoken before the guard has checked
///   it.** A fabricated figure is worse than a slow one.
///
/// Guarding only the finished text satisfies the second and breaks the first.
/// Speaking tokens as they arrive satisfies the first and abandons the second —
/// by the time the guard rejects a number she has already said it out loud.
///
/// The resolution is to make **the sentence** the unit of release. Each complete
/// sentence is guarded the moment it closes, then either released or withheld.
/// She starts speaking after the first sentence rather than after the last, and
/// nothing unchecked ever reaches the speaker.
///
/// ## Why the boundary rule is safety-critical
///
/// Because release depends on it, and health prose is full of decimals.
/// "Your HRV was 23.8 ms" must not become two sentences. Worse, mid-stream the
/// buffer legitimately reads "Your HRV was 23." a moment before the next token
/// turns it into "23.8" — releasing that as a finished sentence would speak a
/// truncated, wrong number.
///
/// One rule handles both: **a terminator only ends a sentence when the next
/// character is whitespace.** In "23.8" the period is followed by a digit, so it
/// is never a boundary; and mid-stream "23." has nothing after it yet, so it is
/// held rather than released.
public struct SentenceStream: Sendable {

    public enum Release: Sendable, Equatable {
        /// Checked and clear — display it and speak it, with the figures it
        /// drew on. The citations come from the same pass that cleared it, so
        /// a displayed chip and a permitted number can never disagree.
        case allow(String, citations: [OutputGuard.Citation])
        /// Checked and rejected. Never displayed, never spoken.
        case withhold(sentence: String, reason: String)
    }

    /// Trailing periods that are part of a word rather than the end of one.
    static let abbreviations: Set<String> = [
        "e.g.", "i.e.", "approx.", "vs.", "dr.", "a.m.", "p.m.", "etc.",
    ]

    static let terminators: Set<Character> = [".", "!", "?"]

    private var buffer = ""
    private let guardCheck: OutputGuard
    private let brief: HealthBrief

    public init(brief: HealthBrief, guardCheck: OutputGuard = OutputGuard()) {
        self.brief = brief
        self.guardCheck = guardCheck
    }

    /// Feed a token. Returns whatever became releasable because of it —
    /// usually nothing, occasionally one sentence, rarely more.
    public mutating func append(_ token: String) -> [Release] {
        buffer += token
        let (complete, remainder) = Self.splitComplete(buffer)
        buffer = remainder
        return complete.map(check)
    }

    /// Call when generation ends. Releases any trailing text that never got a
    /// terminator — a response truncated by a token limit still has to be
    /// checked rather than dropped or silently shown.
    public mutating func finish() -> [Release] {
        let trailing = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return trailing.isEmpty ? [] : [check(trailing)]
    }

    private func check(_ sentence: String) -> Release {
        switch guardCheck.check(sentence, against: brief) {
        case .allow:
            return .allow(sentence,
                          citations: guardCheck.citations(in: sentence, against: brief))
        case .rewrite(let reason), .block(let reason):
            // No distinction at this layer. Once a sentence is suspect it is not
            // spoken, and the caller decides whether to retry or apologise.
            return .withhold(sentence: sentence, reason: reason)
        }
    }

    // MARK: - Boundary detection

    /// Split off every complete sentence, returning them with what is left over.
    static func splitComplete(_ text: String) -> (complete: [String], remainder: String) {
        var sentences: [String] = []
        var start = text.startIndex
        var i = text.startIndex

        while i < text.endIndex {
            defer { i = text.index(after: i) }
            guard terminators.contains(text[i]) else { continue }

            let next = text.index(after: i)
            // The single rule: a terminator only closes a sentence when
            // whitespace follows. Decimals and mid-stream truncation both fall
            // out of this for free.
            guard next < text.endIndex, text[next].isWhitespace else { continue }

            let candidate = String(text[start...i])
            if let lastWord = candidate.split(separator: " ").last,
               abbreviations.contains(lastWord.lowercased()) {
                continue
            }

            sentences.append(candidate.trimmingCharacters(in: .whitespacesAndNewlines))
            start = next
        }

        return (sentences, String(text[start...]))
    }
}

/// A reference-typed, lock-protected wrapper around `SentenceStream`.
///
/// Exists because the token callback is `@escaping @Sendable` and the stream is
/// a mutating struct — the two do not meet without either a reference type or
/// an `unsafe` escape hatch. A small lock is the honest version of that, and
/// the cost is nothing against generation.
public final class SentenceBuffer: @unchecked Sendable {

    private var stream: SentenceStream
    private let lock = NSLock()

    public init(brief: HealthBrief, guardCheck: OutputGuard = OutputGuard()) {
        self.stream = SentenceStream(brief: brief, guardCheck: guardCheck)
    }

    public func append(_ token: String) -> [SentenceStream.Release] {
        lock.lock()
        defer { lock.unlock() }
        return stream.append(token)
    }

    public func finish() -> [SentenceStream.Release] {
        lock.lock()
        defer { lock.unlock() }
        return stream.finish()
    }
}
