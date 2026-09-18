import Foundation
import AURACore
import AURAAnalytics

/// Runs one exchange: build the prompt, stream the answer, guard every sentence
/// before it is released.
///
/// The only place the language model and the health data meet, and the shape of
/// that meeting is the point: the model receives a `HealthBrief` of finished
/// figures and is asked for prose about them. It is never asked to compute
/// anything, because it is unreliable at exactly the arithmetic that matters
/// here and the subject is the reader's own body.
public actor Conversation {

    public enum Event: Sendable {
        /// A checked sentence, with the figures it drew on.
        case sentence(String, citations: [OutputGuard.Citation])
        /// A sentence the guard refused. Never shown to the user — surfaced so
        /// the app can retry or apologise rather than silently truncating.
        case withheld(reason: String)
        case finished(full: String)
        case failed(String)
    }

    private let model: any LanguageModel
    private let briefBuilder: BriefBuilder

    public init(model: any LanguageModel, briefBuilder: BriefBuilder) {
        self.model = model
        self.briefBuilder = briefBuilder
    }

    /// Answer `question` about `day`, emitting events as the answer forms.
    public func answer(
        _ question: String,
        about day: CalendarDay,
        onEvent: @escaping @Sendable (Event) -> Void
    ) async {
        do {
            let brief = try await briefBuilder.brief(for: day)
            let buffer = SentenceBuffer(brief: brief)

            // A closure value, not a local `func`: it is captured by the
            // `@Sendable` token callback passed to `model.complete` below, and
            // a local function captured that way must itself be `@Sendable` --
            // Swift does not infer that for `func` declarations. `onEvent` is
            // already `@Sendable`, so the closure body is fine as written; only
            // the declaration form needed to change.
            let emit: @Sendable ([SentenceStream.Release]) -> Void = { releases in
                for release in releases {
                    switch release {
                    case .allow(let sentence, let citations):
                        onEvent(.sentence(sentence, citations: citations))
                    case .withhold(_, let reason): onEvent(.withheld(reason: reason))
                    }
                }
            }

            let full = try await model.complete(
                system: Self.systemPrompt,
                user: Self.userPrompt(question: question, brief: brief)
            ) { token in
                emit(buffer.append(token))
            }

            // Anything that never got a terminator is still checked, not
            // dropped: a response cut off by the token limit must not reach
            // the user unguarded.
            emit(buffer.finish())
            onEvent(.finished(full: full))
        } catch is CancellationError {
            // Interrupting her is normal, not an error.
        } catch {
            onEvent(.failed(error.localizedDescription))
        }
    }

    // MARK: - Prompting

    /// Her brief, in the other sense.
    ///
    /// Short on purpose. A long persona prompt is tokens spent before the first
    /// one comes back, and it competes with the figures for the model's
    /// attention. The only non-negotiable instruction is the arithmetic one.
    static let systemPrompt = """
        You are AURA, a health companion. You are talking to the person whose \
        data this is, about their own body.

        The DATA block contains figures that have already been computed from \
        their Apple Health history. Those figures are correct.

        Rules, in order of importance:

        1. Never state a number that is not in the DATA block. Do not add, \
        average, convert between windows, or estimate. If a figure is not \
        there, say you do not have it. Every number you write is checked \
        against the data before it reaches them.
        2. You observe; you do not diagnose, prescribe, or advise on \
        medication. If something looks worth a doctor's attention, say that \
        plainly without naming a condition.
        3. Respect the confidence on each observation. A weak signal is worth \
        mentioning as a maybe, never as a finding.
        4. Where days are missing, say so rather than talking as if the window \
        were complete.
        5. Use the CONTEXT block to explain what the numbers show. A drop \
        during a week they marked as illness is illness, not decline. Never \
        treat context as a measurement, and never invent context that is not \
        there.
        6. Be warm, specific and brief. Two or three sentences unless they \
        asked for more. You are speaking aloud, so write the way people talk.
        """

    static func userPrompt(question: String, brief: HealthBrief) -> String {
        var lines: [String] = ["DATA for \(brief.range.end):"]

        for figure in brief.figures {
            var line = "- \(figure.label): \(format(figure.value)) \(figure.unit)"
            if let percentile = figure.personalPercentile {
                line += " (their own \(Int((percentile * 100).rounded()))th percentile)"
            }
            if let change = figure.changePercent {
                line += String(format: " [%+.1f%% vs previous window]", change)
            }
            lines.append(line)
        }

        for goal in brief.goals {
            lines.append("- \(goal.label) goal: \(format(goal.target)), "
                + "at \(format(goal.percent))% — \(goal.isMet ? "met" : "not met")")
        }

        if !brief.memory.isEmpty {
            lines.append("")
            lines.append("CONTEXT THEY GAVE YOU (their words, not measurements):")
            for recollection in brief.memory {
                lines.append("- \(recollection.text)")
            }
        }

        if !brief.observations.isEmpty {
            lines.append("")
            lines.append("OBSERVATIONS (confidence 0-1; below 0.5 is weak):")
            for observation in brief.observations {
                lines.append(String(format: "- [%.2f] %@",
                                    observation.confidence, observation.text))
            }
        }

        if brief.missingDays > 0 {
            lines.append("")
            lines.append("NOTE: \(brief.missingDays) day(s) in this window have no data.")
        }

        lines.append("")
        lines.append("QUESTION: \(question)")
        return lines.joined(separator: "\n")
    }

    /// Whole numbers read as whole numbers. "10172 steps" is what a person
    /// says; "10171.6 steps" is what a database says.
    static func format(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}
