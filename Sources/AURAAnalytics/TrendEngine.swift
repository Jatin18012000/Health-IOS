import Foundation
import AURACore

/// Every number the dashboard shows and every number AURA says comes from here.
///
/// Deterministic, testable arithmetic, deliberately kept out of the language
/// model's hands. A companion that misreports your own resting heart rate is
/// not a bug — it is misinformation about your body, delivered warmly.
///
/// Two rules run through all of it:
///
///   1. **Personal baselines, never population norms.** Every comparison is
///      against this person's own history. "Higher than your own last 90 days"
///      is a fact; "above average for your age" is unlicensed medicine.
///   2. **Say how much you know.** Every figure carries its sample size and
///      every observation its confidence. Over 1,450 days almost any two
///      metrics correlate weakly, and surfacing r = 0.11 as an insight is how a
///      health app starts telling people comforting nonsense.
public struct TrendEngine: Sendable {

    let store: any AnalyticsStore

    public init(store: any AnalyticsStore) { self.store = store }

    // MARK: - Trend

    public struct Trend: Sendable {
        public let metric: String
        public let windowDays: Int
        public let current: Double?
        public let previous: Double?
        public let changePercent: Double?
        public let slopePerDay: Double?
        public let coveredDays: Int
        /// Reported, never silently averaged over. "I only have four days of
        /// this week" is a better answer than a confident mean of four days.
        public let missingDays: Int
    }

    public func trend(metric: String, endingOn end: CalendarDay,
                      days: Int = AnalyticsConfig.comparisonDays) async throws -> Trend {
        let current = DayRange.lastDays(days, endingOn: end)
        let previousEnd = current.start.adding(days: -1)
        let previous = DayRange.lastDays(days, endingOn: previousEnd)

        let cur = try await values(metric, in: current)
        let prev = try await values(metric, in: previous)

        let curMean = Stats.mean(cur)
        let prevMean = Stats.mean(prev)
        var change: Double?
        if let c = curMean, let p = prevMean, p != 0 {
            change = (c - p) / abs(p) * 100
        }

        return Trend(metric: metric, windowDays: days,
                     current: curMean, previous: prevMean, changePercent: change,
                     slopePerDay: Stats.slope(cur),
                     coveredDays: cur.count, missingDays: days - cur.count)
    }

    // MARK: - Correlation

    public struct Correlation: Sendable {
        public let a: String
        public let b: String
        public let r: Double?
        public let n: Int
        /// Carried out with the finding so she can hedge honestly rather than
        /// either dropping a real signal or overselling a coincidence.
        public let confidence: Double
        public var isReportable: Bool { r != nil }
    }

    public func correlation(_ a: String, _ b: String, endingOn end: CalendarDay,
                            days: Int = AnalyticsConfig.baselineDays) async throws -> Correlation {
        let range = DayRange.lastDays(days, endingOn: end)
        let da = Dictionary(uniqueKeysWithValues:
            try await store.daily(metric: a, in: range).compactMap { m in
                m.value.map { (m.day, $0) } })
        let db = Dictionary(uniqueKeysWithValues:
            try await store.daily(metric: b, in: range).compactMap { m in
                m.value.map { (m.day, $0) } })

        let common = Set(da.keys).intersection(db.keys).sorted()
        guard common.count >= AnalyticsConfig.minCorrelationSamples else {
            return Correlation(a: a, b: b, r: nil, n: common.count, confidence: 0)
        }

        let r = Stats.pearson(common.map { da[$0]! }, common.map { db[$0]! })
        return Correlation(
            a: a, b: b, r: r, n: common.count,
            confidence: r.map { Swift.min(1.0, abs($0) / AnalyticsConfig.strongCorrelation) } ?? 0)
    }

    // MARK: - Figure

    /// One metric's value for a day, with its personal context.
    public struct Figure: Sendable {
        public let metric: String
        public let title: String
        public let value: Double
        public let unit: Unit
        /// 0...1 against this person's own baseline window, inverted for
        /// metrics where lower is better.
        public let personalPercentile: Double?
        public let baselineMean: Double?
        public let baselineCount: Int
        public let changePercent: Double?
        public let anomalyZ: Double?
    }

    public func figure(_ metric: String, on day: CalendarDay) async throws -> Figure? {
        let today = try await store.daily(metric: metric,
                                          in: DayRange(start: day, end: day))
        guard let row = today.first, let value = row.value,
              let spec = MetricCatalog[metric] else { return nil }

        let population = try await baseline(metric, endingOn: day)
        var percentile = Stats.percentile(of: value, in: population)
        if AnalyticsConfig.lowerIsBetter.contains(metric), let p = percentile {
            percentile = 1 - p
        }

        return Figure(
            metric: metric, title: spec.title, value: value, unit: row.unit,
            personalPercentile: percentile,
            baselineMean: Stats.mean(population),
            baselineCount: population.count,
            changePercent: try await trend(metric: metric, endingOn: day).changePercent,
            anomalyZ: Stats.modifiedZ(of: value, in: population))
    }

    // MARK: - Helpers

    func baseline(_ metric: String, endingOn day: CalendarDay,
                  days: Int = AnalyticsConfig.baselineDays) async throws -> [Double] {
        try await values(metric, in: .lastDays(days, endingOn: day))
    }

    private func values(_ metric: String, in range: DayRange) async throws -> [Double] {
        try await store.daily(metric: metric, in: range).compactMap(\.value)
    }
}
