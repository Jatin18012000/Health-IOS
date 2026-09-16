import Testing
import Foundation
@testable import AURAIntelligence
@testable import AURACore

/// The same worked examples `tools/output_guard.py --self-test` runs.
///
/// Both the fabrication cases exist because an earlier version of the guard
/// passed them. Keeping them is the point: they are the specific holes, not
/// illustrative ones.
@Suite("Output guard")
struct OutputGuardTests {

    static let brief = HealthBrief(
        range: DayRange(start: CalendarDay(year: 2026, month: 8, day: 15),
                        end: CalendarDay(year: 2026, month: 9, day: 13)),
        comparisonRange: nil,
        figures: [
            .init(metric: "StepCount", label: "Steps", value: 10171.6,
                  unit: "count", changePercent: 18.3, personalPercentile: 0.79),
            .init(metric: "HeartRateVariabilitySDNN", label: "HRV (SDNN)", value: 23.797,
                  unit: "ms", changePercent: -6.5, personalPercentile: 0.06),
        ],
        observations: [
            .init(text: "StepCount and HRV move oppositely (r=-0.30, n=62)",
                  confidence: 0.6),
        ],
        missingDays: 0)

    private func problems(_ text: String) -> [OutputGuard.Problem] {
        OutputGuard().problems(in: text, against: Self.brief)
    }

    // MARK: Honest prose must pass

    @Test("figures quoted directly are allowed")
    func directQuotes() {
        #expect(problems("Your HRV was 23.8 ms and you walked 10,172 steps.").isEmpty)
    }

    @Test("a percentile may be spoken as a percentage")
    func fractionToPercent() {
        // 0.79 -> "79%". Blocking this would make the guard unusable.
        #expect(problems("That puts you at the 79th percentile.").isEmpty)
    }

    @Test("a large count may be shortened")
    func thousandsShorthand() {
        #expect(problems("About 10.2k steps today.").isEmpty)
    }

    @Test("she may repeat a correlation the analysis handed her")
    func observationNumbers() {
        #expect(problems("Steps and HRV move oppositely (r=-0.30 across 62 days).").isEmpty)
    }

    // MARK: Fabrication must be caught

    @Test("a plausible invented figure is caught")
    func inventedFigure() {
        // 31.2 is close to nothing in the brief — but an earlier version of the
        // guard allowed it, because a 5% RELATIVE tolerance around the free
        // number 30 accepted everything from 28.5 to 31.5.
        let found = problems("Your HRV was 31.2 ms last night.")
        #expect(found.contains { $0.kind == .fabricatedFigure && $0.detail == "31.2" })
    }

    @Test("a figure for a metric not in the brief at all is caught")
    func metricNotPresent() {
        // Same root cause: the free number 60 accepted 57 through 63.
        let found = problems("Your resting heart rate averaged 58 bpm this week.")
        #expect(found.contains { $0.kind == .fabricatedFigure && $0.detail == "58" })
    }

    @Test("a confident figure for an uncomputed window is caught")
    func uncomputedWindow() {
        let found = problems("You averaged 12,400 steps over the last fortnight.")
        #expect(found.contains { $0.kind == .fabricatedFigure })
    }

    // MARK: Clinical overreach must be blocked

    @Test("diagnosis, prescription and inference are all blocked")
    func clinicalLanguage() {
        for text in ["You have sleep apnea.",
                     "You should reduce your dose of the medication.",
                     "This could be a sign of an underlying condition."] {
            let verdict = OutputGuard().check(text, against: Self.brief)
            guard case .block = verdict else {
                Issue.record("not blocked: \(text)")
                continue
            }
        }
    }

    @Test("a fabricated figure is a rewrite, not a block")
    func fabricationIsRecoverable() {
        // The surrounding prose is usually fine and worth keeping once the
        // invented number is gone.
        let verdict = OutputGuard().check("Your HRV was 31.2 ms last night.",
                                          against: Self.brief)
        guard case .rewrite = verdict else {
            Issue.record("expected a rewrite, got \(verdict)")
            return
        }
    }

    // MARK: The derivation rule that caused a hole

    @Test("minute derivations apply only to minute-valued metrics")
    func derivationsAreTypeAware() {
        // 91.4 % 60 = 31.4. Applying the duration derivation to a score
        // component quietly authorised "31" — which is how the fabricated
        // 31.2 ms HRV above got through in the first place.
        let asScore = OutputGuard.derivations(of: 91.4, as: .plain)
        #expect(!asScore.contains { abs($0 - 31) < 0.6 })

        let asDuration = OutputGuard.derivations(of: 91.4, as: .durationMinutes)
        #expect(asDuration.contains { abs($0 - 31) < 0.6 })
    }
}
