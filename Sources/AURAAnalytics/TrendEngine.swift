import Foundation
import AURACore
import AURAStore

/// Every number the dashboard shows and every number AURA says comes from here.
///
/// Deterministic, unit-tested arithmetic, deliberately kept out of the language
/// model's hands -- see the reasoning on `HealthBrief`.
public struct TrendEngine: Sendable {
    let store: any HealthStore

    public init(store: any HealthStore) { self.store = store }

    public struct Trend: Sendable {
        public let metric: String
        public let current: Double?
        public let previous: Double?
        public let changePercent: Double?
        /// Least-squares slope per day over the window.
        public let slopePerDay: Double?
        public let coveredDays: Int
        public let missingDays: Int
    }

    /// Compare a window against the equivalent window immediately before it.
    public func trend(metric: String, over range: DayRange) async throws -> Trend {
        // M3
        fatalError("unimplemented")
    }

    /// Correlate two metrics over a window.
    ///
    /// Returns Pearson's r *with* the sample size, and the caller is expected
    /// to respect it. With four years of data almost any pair of metrics
    /// correlates at some weak level; surfacing `r = 0.11` as an insight is
    /// how a health dashboard starts telling people comforting nonsense.
    /// `HealthBrief.Observation.confidence` exists so weak findings can be
    /// carried honestly instead of dropped or oversold.
    public func correlation(_ a: String, _ b: String,
                            over range: DayRange) async throws -> (r: Double, n: Int) {
        // M3
        fatalError("unimplemented")
    }
}

/// The composite 0-100 figure on the dashboard.
///
/// Weights are explicit and documented rather than tuned until the number looks
/// flattering. A score that cannot be explained to the person it describes is
/// decoration, so `Breakdown` carries every component out with it.
public struct HealthScore: Sendable {
    public struct Breakdown: Sendable {
        public let activity: Double?
        public let sleep: Double?
        public let heart: Double?
        public let recovery: Double?
        /// Components with no data are nil rather than zero -- a missing metric
        /// must not read as a failing one.
        public let weightsApplied: [String: Double]
    }

    public let value: Double
    public let breakdown: Breakdown
}
