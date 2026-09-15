import Foundation
import AURACore
import AURAAnalytics

/// Assembles the `HealthBrief` handed to the language model.
///
/// A few hundred tokens, because the arithmetic has already happened in
/// `AURAAnalytics`. Four years of samples is on the order of 40 million tokens
/// and fits in no context window on any machine — but it does not need to,
/// because the model is not being asked to analyse anything. It is being asked
/// to write about figures that are already correct.
public struct BriefBuilder: Sendable {

    let trends: TrendEngine
    let scores: HealthScoreEngine

    /// The metrics a general brief covers. Deliberately short: a brief that
    /// lists forty numbers produces prose that lists forty numbers.
    static let headline = [
        "StepCount", "ActiveEnergyBurned", "DistanceWalkingRunning",
        "AppleExerciseTime", "RestingHeartRate", "HeartRateVariabilitySDNN",
        "TimeInDaylight",
    ]

    /// Pairs worth testing for a relationship. Chosen because each has a
    /// plausible physiological mechanism — not mined by trying every
    /// combination, which over 40 metrics would surface something "significant"
    /// by chance alone.
    static let correlationPairs = [
        ("StepCount", "HeartRateVariabilitySDNN"),
        ("StepCount", "RestingHeartRate"),
        ("AppleExerciseTime", "HeartRateVariabilitySDNN"),
        ("TimeInDaylight", "HeartRateVariabilitySDNN"),
    ]

    let goals: Goals

    public init(store: any AnalyticsStore, goals: Goals = .default) {
        self.trends = TrendEngine(store: store)
        self.scores = HealthScoreEngine(store: store)
        self.goals = goals
    }

    public func brief(for day: CalendarDay,
                      window: Int = AnalyticsConfig.comparisonDays) async throws -> HealthBrief {
        var figures: [HealthBrief.Figure] = []
        var goalProgress: [HealthBrief.GoalProgress] = []
        var observations: [HealthBrief.Observation] = []

        for metric in Self.headline {
            guard let f = try await trends.figure(metric, on: day) else { continue }
            figures.append(HealthBrief.Figure(
                metric: f.metric, label: f.title, value: f.value,
                unit: f.unit.rawValue, changePercent: f.changePercent,
                personalPercentile: f.personalPercentile))

            if let p = goals.progress(for: f.metric, value: f.value) {
                goalProgress.append(HealthBrief.GoalProgress(
                    metric: f.metric, label: f.title, target: p.target,
                    value: p.value, percent: p.percent, isMet: p.isMet))
            }

            // An anomaly is "unusual for you", measured against your own median
            // and MAD — not against anybody else.
            if let z = f.anomalyZ, abs(z) >= AnalyticsConfig.outlierZ {
                let direction = z > 0 ? "well above" : "well below"
                observations.append(HealthBrief.Observation(
                    text: "\(f.title) is \(direction) your usual range "
                        + "(\(Int(f.value.rounded())) \(f.unit.rawValue))",
                    confidence: Swift.min(1, abs(z) / (AnalyticsConfig.outlierZ * 2))))
            }
        }

        for (a, b) in Self.correlationPairs {
            let c = try await trends.correlation(a, b, endingOn: day)
            guard let r = c.r, abs(r) >= 0.2 else { continue }
            let together = r > 0 ? "together" : "oppositely"
            observations.append(HealthBrief.Observation(
                text: "\(a) and \(b) move \(together) "
                    + "(r=\(String(format: "%.2f", r)), n=\(c.n))",
                confidence: c.confidence))
        }

        let range = DayRange.lastDays(window, endingOn: day)
        let trend = try await trends.trend(metric: "StepCount", endingOn: day, days: window)

        return HealthBrief(
            range: range,
            comparisonRange: DayRange.lastDays(window, endingOn: range.start.adding(days: -1)),
            figures: figures,
            goals: goalProgress,
            observations: observations.sorted { $0.confidence > $1.confidence },
            // So she can say "I only have four days of this week" rather than
            // quietly averaging over a gap.
            missingDays: trend.missingDays)
    }
}
