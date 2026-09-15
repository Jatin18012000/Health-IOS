import Foundation
import AURACore

/// The composite 0–100 on the dashboard.
///
/// Each component is this person's own percentile against their last year, so
/// the score answers "how does today compare with my own year" and nothing. No
/// population norms, no invented thresholds, no pretending to know what anyone's
/// heart rate *should* be.
///
/// **Known consequence, and it is a product decision rather than a bug:**
/// percentiles are self-referential, so the score is centred on 50 by
/// construction. Measured over four years of real data it runs mean ≈ 51 with a
/// standard deviation of ≈ 14. That means **a sustained improvement is slow to
/// show in it** — improve for eight weeks and your baseline follows you, just
/// more slowly at 365 days than at 90. `docs/DECISIONS_PENDING.md` §1 records
/// the decision and what it did and did not fix.
public struct HealthScoreEngine: Sendable {

    let store: any AnalyticsStore
    let trends: TrendEngine

    public init(store: any AnalyticsStore) {
        self.store = store
        self.trends = TrendEngine(store: store)
    }

    public struct Score: Sendable {
        public let value: Double?
        public let components: [ScoreComponent: Double]
        /// Weights as actually applied, after redistribution.
        public let weights: [ScoreComponent: Double]
        public let missing: [ScoreComponent]
        /// How much of the day the store has, 0...1.
        public let completeness: Double
        /// True when the day is still in progress. The UI must show "day in
        /// progress" rather than the number: the last day of any import is
        /// almost always partial, and a companion that reports collapsing
        /// health because you exported before lunch has spent its credibility.
        public let isPartial: Bool

        public var isPublishable: Bool { value != nil && !isPartial }
    }

    public func score(on day: CalendarDay) async throws -> Score {
        var components: [ScoreComponent: Double] = [:]

        // Activity: the mean percentile across whichever of these exist.
        let activity = try await [
            trends.figure("StepCount", on: day),
            trends.figure("ActiveEnergyBurned", on: day),
            trends.figure("AppleExerciseTime", on: day),
        ].compactMap { $0?.personalPercentile }
        if let m = Stats.mean(activity) {
            components[.activity] = m * 100
        }

        if let sleep = try await sleepScore(on: day) {
            components[.sleep] = sleep
        }

        if let hr = try await trends.figure("RestingHeartRate", on: day),
           let p = hr.personalPercentile {
            components[.heart] = p * 100
        }

        if let hrv = try await trends.figure("HeartRateVariabilitySDNN", on: day),
           let p = hrv.personalPercentile {
            components[.recovery] = p * 100
        }

        let completeness = try await self.completeness(of: day)
        let partial = completeness < AnalyticsConfig.partialDayThreshold

        guard !components.isEmpty else {
            return Score(value: nil, components: [:], weights: [:],
                         missing: ScoreComponent.allCases,
                         completeness: completeness, isPartial: partial)
        }

        // A component with no data is absent, and its weight is redistributed
        // over the ones that do have data. A missing metric must never read as
        // a failing one.
        let totalWeight = components.keys
            .compactMap { AnalyticsConfig.scoreWeights[$0] }
            .reduce(0, +)
        var applied: [ScoreComponent: Double] = [:]
        for key in components.keys {
            applied[key] = (AnalyticsConfig.scoreWeights[key] ?? 0) / totalWeight
        }
        let value = components.reduce(0.0) { $0 + $1.value * (applied[$1.key] ?? 0) }

        return Score(
            value: (value * 10).rounded() / 10,
            components: components.mapValues { ($0 * 10).rounded() / 10 },
            weights: applied,
            missing: ScoreComponent.allCases.filter { components[$0] == nil },
            completeness: completeness,
            isPartial: partial)
    }

    // MARK: - Components

    private func sleepScore(on day: CalendarDay) async throws -> Double? {
        let nights = try await store.nights(in: DayRange(start: day, end: day))
        guard let night = nights.first else { return nil }

        // Staged and in-bed-only nights are not comparable quantities, so a
        // night is only ever ranked against others of its own kind.
        let window = DayRange.lastDays(AnalyticsConfig.baselineDays, endingOn: day)
        let population = try await store.nights(in: window)
            .filter { $0.isStaged == night.isStaged }
            .map(\.asleepMinutes)

        guard population.count >= AnalyticsConfig.minBaselineSamples,
              let percentile = Stats.percentile(of: night.asleepMinutes, in: population)
        else { return nil }
        var score = percentile * 100

        // Efficiency only means something on a staged night. On an in-bed-only
        // night it is an artefact of when the phone decided you went to bed.
        if night.isStaged, let efficiency = night.efficiency {
            score = 0.7 * score + 0.3 * Swift.min(100, efficiency)
        }
        return score
    }

    /// How much of a day the store actually holds, 0...1.
    ///
    /// Measured from the day's last sample rather than from the clock, because
    /// the store may be read long after the import that filled it.
    private func completeness(of day: CalendarDay) async throws -> Double {
        let domains = try await store.daily(domain: .activity, on: day)
        guard !domains.isEmpty else { return 0 }

        let samples = try await store.samples(metric: "StepCount",
                                              in: DayRange(start: day, end: day))
        guard let last = samples.map(\.end).max() else { return 0 }
        let midnight = day.date()
        return Swift.max(0, Swift.min(1, last.timeIntervalSince(midnight) / 86_400))
    }
}
