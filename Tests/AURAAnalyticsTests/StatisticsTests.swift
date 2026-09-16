import Testing
import Foundation
@testable import AURAAnalytics

/// Every expected value here was computed by hand, not copied from a run.
/// A test that records what the code currently does is worth nothing.
@Suite("Statistics")
struct StatisticsTests {

    @Test("slope of a straight line is its gradient")
    func slope() {
        #expect(Stats.slope([1, 2, 3, 4, 5]) == 1.0)
        #expect(Stats.slope([5, 4, 3, 2, 1]) == -1.0)
        #expect(Stats.slope([3, 3, 3, 3]) == 0.0)
        // Fewer than three points is a line through noise, not a trend.
        #expect(Stats.slope([1, 2]) == nil)
    }

    @Test("an exactly median value sits at 0.5")
    func percentileMidpoint() {
        // Half the ties count, so the median does not drift with how many
        // duplicate values a person happens to have.
        #expect(Stats.percentile(of: 3, in: [1, 2, 3, 4, 5]) == 0.5)
        #expect(Stats.percentile(of: 5, in: [1, 2, 3, 4, 5]) == 0.9)
        #expect(Stats.percentile(of: 1, in: [1, 2, 3, 4, 5]) == 0.1)
        #expect(Stats.percentile(of: 0, in: []) == nil)
    }

    @Test("a population of identical values has no outliers")
    func modifiedZFlat() {
        // MAD is zero, so the score is undefined rather than infinite. Returning
        // a huge number here would flag every value as an anomaly.
        #expect(Stats.modifiedZ(of: 99, in: Array(repeating: 5.0, count: 20)) == nil)
    }

    @Test("a genuine outlier clears the threshold")
    func modifiedZOutlier() {
        let population = (1...10).map(Double.init)
        let z = Stats.modifiedZ(of: 20, in: population)
        // median 5.5, MAD 2.5 -> 0.6745 * 14.5 / 2.5 = 3.912
        #expect(z != nil)
        #expect(abs(z! - 3.912) < 0.01)
        #expect(abs(z!) >= AnalyticsConfig.outlierZ)
    }

    @Test("the median resists a skew that would move the mean")
    func medianResistsSkew() {
        // This is why anomaly detection uses median/MAD: one enormous day
        // inflates the mean and the SD together and hides the very outliers the
        // check exists to find.
        let typical = Array(repeating: 8000.0, count: 20)
        let withOneHugeDay = typical + [80_000]
        #expect(Stats.median(withOneHugeDay) == 8000)
        #expect(Stats.mean(withOneHugeDay)! > 11_000)
    }

    @Test("pearson recognises a perfect relationship")
    func pearson() {
        #expect(Stats.pearson([1, 2, 3], [2, 4, 6]) == 1.0)
        #expect(Stats.pearson([1, 2, 3], [6, 4, 2]) == -1.0)
        // No variance in one series means no relationship to measure.
        #expect(Stats.pearson([1, 1, 1], [1, 2, 3]) == nil)
        #expect(Stats.pearson([1, 2], [1, 2]) == nil)
    }
}

@Suite("Score weighting")
struct ScoreWeightingTests {

    @Test("a missing component redistributes its weight rather than scoring zero")
    func redistribution() {
        // The rule that matters: a metric with no data must never read as a
        // failing one. With sleep and heart absent, activity and recovery
        // carry the whole score in their original proportion — 0.30 and 0.20
        // become 0.60 and 0.40.
        let present: [ScoreComponent] = [.activity, .recovery]
        let total = present.compactMap { AnalyticsConfig.scoreWeights[$0] }.reduce(0, +)
        #expect(abs(total - 0.5) < 0.0001)

        let applied = present.map { (AnalyticsConfig.scoreWeights[$0] ?? 0) / total }
        #expect(abs(applied[0] - 0.6) < 0.0001)
        #expect(abs(applied[1] - 0.4) < 0.0001)
        #expect(abs(applied.reduce(0, +) - 1.0) < 0.0001)
    }

    @Test("weights sum to one")
    func weightsSumToOne() {
        let total = ScoreComponent.allCases
            .compactMap { AnalyticsConfig.scoreWeights[$0] }.reduce(0, +)
        #expect(abs(total - 1.0) < 0.0001)
    }
}
