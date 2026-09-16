import Testing
import Foundation
@testable import AURAIntelligence
@testable import AURACore

/// Citations are the positives the guard used to throw away — proof that a
/// number she said came from somewhere, not just that it wasn't invented.
///
/// Both ambiguity cases below are here because the first implementation got
/// them wrong. They are the specific failures, not illustrations.
@Suite("Citations")
struct CitationTests {

    static let brief = HealthBrief(
        range: DayRange(start: CalendarDay(year: 2025, month: 9, day: 14),
                        end: CalendarDay(year: 2026, month: 9, day: 13)),
        comparisonRange: nil,
        figures: [
            .init(metric: "StepCount", label: "Steps", value: 10_171.6,
                  unit: "count", changePercent: 18.3, personalPercentile: 0.86),
            .init(metric: "HeartRateVariabilitySDNN", label: "HRV (SDNN)", value: 23.797,
                  unit: "ms", changePercent: -6.5, personalPercentile: 0.06),
        ],
        goals: [
            .init(metric: "StepCount", label: "Steps", target: 8_000,
                  value: 10_171.6, percent: 127.1, isMet: true),
        ],
        observations: [
            .init(text: "StepCount and HRV move oppositely (r=-0.30, n=62)",
                  confidence: 0.6),
        ],
        missingDays: 0)

    private func cited(_ text: String) -> Set<String> {
        Set(OutputGuard().citations(in: text, against: Self.brief).map(\.metric))
    }

    @Test("a figure's own value cites it")
    func primaryValue() {
        #expect(cited("You walked 10,172 steps.") == ["StepCount"])
    }

    @Test("several numerals from one fact produce one chip")
    func oneChipPerFigure() {
        // Value, goal and progress all point at the same metric. Three chips
        // reading "Steps" would be noise.
        #expect(cited("You walked 10,172 steps — 127% of your 8,000 goal.")
                == ["StepCount"])
    }

    @Test("an ambiguous small number corroborates rather than cites")
    func ambiguityPrefersCitedMetric() {
        // The "6" matches HRV's percentile (0.06 -> 6). Before the rule that
        // an already-cited metric wins, it could attach to anything else that
        // happened to round to 6.
        #expect(cited("Your HRV was 23.8 ms, the 6th percentile.")
                == ["HeartRateVariabilitySDNN"])
    }

    @Test("a lone weak number is a coincidence, not a citation")
    func weakNumbersDoNotCite() {
        // "a couple of days" must not cite whatever figure happens to round
        // near 2. Free numbers are never findings.
        #expect(cited("That is worth watching for a couple of days.").isEmpty)
        #expect(cited("Give it 2 more days.").isEmpty)
    }

    @Test("two genuine facts produce two chips")
    func multipleFigures() {
        #expect(cited("You walked 10,172 steps and your HRV was 23.8 ms.")
                == ["StepCount", "HeartRateVariabilitySDNN"])
    }

    @Test("a citation reports the numeral as written")
    func reportsTheNumeralAsWritten() {
        // Thousands separators and all — the chip should match what she said,
        // not a reformatted version of it.
        let citations = OutputGuard().citations(in: "You walked 10,172 steps.",
                                                against: Self.brief)
        #expect(citations.first?.matched == "10,172")
        #expect(citations.first?.label == "Steps")
    }

    @Test("a released sentence carries its citations")
    func releasedWithCitations() {
        // The citations come from the same pass that cleared the sentence, so a
        // displayed chip and a permitted number cannot disagree.
        var stream = SentenceStream(brief: Self.brief)
        var citations: [OutputGuard.Citation] = []
        for release in stream.append("You walked 10,172 steps. ") {
            if case .allow(_, let found) = release { citations = found }
        }
        #expect(citations.map(\.metric) == ["StepCount"])
    }

    @Test("a withheld sentence carries none")
    func withheldHasNoCitations() {
        var stream = SentenceStream(brief: Self.brief)
        var allowed = 0
        for release in stream.append("Your resting heart rate was 58 bpm. ") {
            if case .allow = release { allowed += 1 }
        }
        #expect(allowed == 0)
    }
}
