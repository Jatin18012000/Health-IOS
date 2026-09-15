import Testing
import Foundation
@testable import AURAIntelligence
@testable import AURACore

/// The same worked cases as the prototype in the scratch harness, plus the
/// token-by-token replay that is the one that actually matters.
///
/// Boundary detection is safety-critical here: a sentence is released to the
/// speaker the moment it closes, so getting a boundary wrong means speaking a
/// truncated number.
@Suite("Sentence boundaries")
struct SentenceStreamTests {

    private func split(_ text: String) -> [String] {
        SentenceStream.splitComplete(text).complete
    }

    @Test("a decimal is not a sentence boundary")
    func decimal() {
        // "23.8" — the period is followed by a digit, not whitespace.
        #expect(split("Your HRV was 23.8 ms. ") == ["Your HRV was 23.8 ms."])
    }

    @Test("a trailing digit-period is held, not released")
    func midStreamDecimal() {
        // The dangerous case. Mid-stream the buffer really does read
        // "Your HRV was 23." a moment before the next token makes it "23.8".
        // Releasing it there would speak a wrong number.
        #expect(split("Your HRV was 23.").isEmpty)
        #expect(SentenceStream.splitComplete("Your HRV was 23.").remainder
                == "Your HRV was 23.")
    }

    @Test("ordinary sentences split")
    func plainSentences() {
        #expect(split("You slept 7h 35m. Your HRV was 23.8 ms. ")
                == ["You slept 7h 35m.", "Your HRV was 23.8 ms."])
    }

    @Test("negative decimals inside parentheses survive")
    func correlationText() {
        #expect(split("Steps and HRV move oppositely (r=-0.30, n=62). Moderate. ")
                == ["Steps and HRV move oppositely (r=-0.30, n=62).", "Moderate."])
    }

    @Test("exclamation and question marks close a sentence")
    func otherTerminators() {
        #expect(split("Sleep was 95.4% efficient! Best this week. ")
                == ["Sleep was 95.4% efficient!", "Best this week."])
        #expect(split("Shall we look? Maybe later. ")
                == ["Shall we look?", "Maybe later."])
    }

    @Test("an abbreviation is not a boundary")
    func abbreviation() {
        #expect(split("Try a walk, e.g. after lunch. It helps. ")
                == ["Try a walk, e.g. after lunch.", "It helps."])
    }

    @Test("nothing is released without a terminator")
    func incomplete() {
        #expect(split("No terminator yet").isEmpty)
    }

    @Test("token-by-token, a split decimal never leaks")
    func streamingReplay() {
        // The real shape of the problem: "23", ".", "8" arrive as three tokens.
        let brief = HealthBrief(
            range: DayRange(start: CalendarDay(year: 2026, month: 9, day: 13),
                            end: CalendarDay(year: 2026, month: 9, day: 13)),
            comparisonRange: nil,
            figures: [.init(metric: "HeartRateVariabilitySDNN", label: "HRV",
                            value: 23.8, unit: "ms", changePercent: nil,
                            personalPercentile: 0.06)],
            observations: [], missingDays: 0)

        var stream = SentenceStream(brief: brief)
        var released: [String] = []
        for token in ["Your ", "HRV ", "was ", "23", ".", "8", " ms",
                      ", ", "the ", "6th ", "percentile", ".", " "] {
            for release in stream.append(token) {
                if case .allow(let sentence) = release { released.append(sentence) }
            }
        }
        #expect(released == ["Your HRV was 23.8 ms, the 6th percentile."])
    }

    @Test("a fabricated figure is withheld rather than spoken")
    func guardedRelease() {
        let brief = HealthBrief(
            range: DayRange(start: CalendarDay(year: 2026, month: 9, day: 13),
                            end: CalendarDay(year: 2026, month: 9, day: 13)),
            comparisonRange: nil,
            figures: [.init(metric: "StepCount", label: "Steps", value: 10_172,
                            unit: "count", changePercent: nil, personalPercentile: 0.86)],
            observations: [], missingDays: 0)

        var stream = SentenceStream(brief: brief)
        var withheld = 0
        for release in stream.append("Your resting heart rate was 58 bpm. ") {
            if case .withhold = release { withheld += 1 }
        }
        // This is the whole point of guarding per sentence rather than per
        // response: it is caught before it is spoken, not after.
        #expect(withheld == 1)
    }

    @Test("trailing text with no terminator is still checked on finish")
    func finishChecksTrailing() {
        let brief = HealthBrief(
            range: DayRange(start: CalendarDay(year: 2026, month: 9, day: 13),
                            end: CalendarDay(year: 2026, month: 9, day: 13)),
            comparisonRange: nil, figures: [], observations: [], missingDays: 0)

        var stream = SentenceStream(brief: brief)
        _ = stream.append("Cut off mid thought")
        // Truncation by a token limit must not bypass the guard.
        #expect(stream.finish().count == 1)
    }
}
