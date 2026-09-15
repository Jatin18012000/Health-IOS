import Foundation

/// The statistical primitives, kept apart from anything that reads a database
/// so they can be tested as pure functions.
///
/// Ported from `tools/analytics.py`, which was verified against four years of
/// real data before any of this was written.
public enum Stats {

    public static func mean(_ xs: [Double]) -> Double? {
        xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    public static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        let mid = s.count / 2
        return s.count % 2 == 1 ? s[mid] : (s[mid - 1] + s[mid]) / 2
    }

    /// Least-squares slope, in units per position.
    ///
    /// Reported alongside the simple delta because the two answer different
    /// questions: a delta compares two endpoints and is at the mercy of both;
    /// a slope uses every point in between.
    public static func slope(_ values: [Double]) -> Double? {
        guard values.count >= 3 else { return nil }
        let xs = (0..<values.count).map(Double.init)
        guard let mx = mean(xs), let my = mean(values) else { return nil }
        let denom = xs.reduce(0) { $0 + pow($1 - mx, 2) }
        guard denom != 0 else { return nil }
        let num = zip(xs, values).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        return num / denom
    }

    /// Where `value` sits within `population`, 0...1.
    ///
    /// The fraction below it plus half the ties, so an exactly median value
    /// scores 0.5 rather than drifting with how many duplicates happen to exist.
    public static func percentile(of value: Double, in population: [Double]) -> Double? {
        guard !population.isEmpty else { return nil }
        let below = population.filter { $0 < value }.count
        let ties = population.filter { $0 == value }.count
        return (Double(below) + Double(ties) / 2) / Double(population.count)
    }

    /// Outlier score from the median and MAD rather than mean and SD.
    ///
    /// Health data is skewed and carries its own outliers — one 25,000-step day
    /// inflates the mean and the standard deviation together, hiding the very
    /// anomalies this is meant to find. The median and MAD do not move.
    public static func modifiedZ(of value: Double, in population: [Double]) -> Double? {
        guard population.count >= 10, let med = median(population) else { return nil }
        guard let mad = median(population.map { abs($0 - med) }), mad != 0 else { return nil }
        return 0.6745 * (value - med) / mad
    }

    public static func pearson(_ xs: [Double], _ ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count >= 3,
              let mx = mean(xs), let my = mean(ys) else { return nil }
        let sx = sqrt(xs.reduce(0) { $0 + pow($1 - mx, 2) })
        let sy = sqrt(ys.reduce(0) { $0 + pow($1 - my, 2) })
        guard sx != 0, sy != 0 else { return nil }
        let num = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        return num / (sx * sy)
    }
}

/// Tunable constants, gathered rather than scattered because they are the
/// things most likely to want changing once a real person uses this.
///
/// Several are open questions — see `docs/DECISIONS_PENDING.md`.
///
/// `baselineDays` is 365 by decision. A percentile score is self-referential and
/// therefore centred on 50 by construction, so sustained improvement never shows
/// in it; a year-long window is the cheapest partial fix, because it takes
/// longer for an improvement to be absorbed into the baseline it is measured
/// against.
///
/// It is a *partial* fix, and measurably so. On the reference data it moved the
/// activity component (steps went from the 79th to the 86th percentile once the
/// window covered a less active year) and moved nothing else, because HRV,
/// resting heart rate and staged sleep have less than a year of history behind
/// them. It will pay off for those components as the Watch accumulates history.
public enum AnalyticsConfig {
    public static var baselineDays = 365

    /// Below this many readings, no percentile is produced.
    ///
    /// Ranking a day against three others and calling it "the 100th percentile"
    /// is a number with no information in it. Widening `baselineDays` makes this
    /// *more* likely to bite rather than less: the window now advertises a year
    /// while a sensor that arrived last month still has only a month behind it.
    public static var minBaselineSamples = 14
    public static var comparisonDays = 30
    public static var minCorrelationSamples = 30
    public static var strongCorrelation = 0.5
    public static var outlierZ = 3.5
    /// Below this share of a day elapsed, no composite score is published.
    public static var partialDayThreshold = 0.9

    /// PROVISIONAL. Not derived from anything — see DECISIONS_PENDING §2.
    public static var scoreWeights: [ScoreComponent: Double] = [
        .activity: 0.30, .sleep: 0.30, .heart: 0.20, .recovery: 0.20,
    ]

    /// Metrics where a lower value is the better one, so the percentile inverts.
    public static let lowerIsBetter: Set<String> = [
        "RestingHeartRate", "WalkingHeartRateAverage",
        "AppleSleepingBreathingDisturbances",
    ]
}

public enum ScoreComponent: String, CaseIterable, Sendable, Codable {
    case activity, sleep, heart, recovery
}
