import Foundation

/// Daily targets.
///
/// A **preference**, not a statistic — which is why it lives here rather than in
/// `AnalyticsConfig`, and why nothing in the analytics layer is derived from it.
/// Percentiles and the composite score deliberately ignore goals entirely:
/// *a goal is a number someone picked; a percentile is a fact about the person.*
/// Mixing the two would let an arbitrary target quietly move a figure that is
/// supposed to describe reality.
///
/// Stored as a value so it can become a real user setting without anything
/// downstream changing shape.
public struct Goals: Sendable, Codable, Hashable {

    /// Steps per day.
    ///
    /// 8,000 rather than the customary 10,000. That figure originates in a
    /// 1960s Japanese pedometer marketing campaign — *manpo-kei*, "ten thousand
    /// step meter" — and has no clinical basis. Against the reference user's own
    /// 365-day mean of 6,340, a 10,000 target is cleared about four days in ten;
    /// 8,000 is reachable often enough to mean something when it is missed.
    public var dailySteps: Int

    /// Minutes of recorded exercise per day. Nil until the user sets one — an
    /// unset goal shows no ring rather than a target nobody chose.
    public var dailyExerciseMinutes: Int?

    /// Hours asleep. Nil by default for the same reason, and because sleep
    /// responds badly to being treated as a target to hit.
    public var nightlySleepHours: Double?

    public init(dailySteps: Int = 8_000,
                dailyExerciseMinutes: Int? = nil,
                nightlySleepHours: Double? = nil) {
        self.dailySteps = dailySteps
        self.dailyExerciseMinutes = dailyExerciseMinutes
        self.nightlySleepHours = nightlySleepHours
    }

    public static let `default` = Goals()

    /// Progress against a goal, or nil when no goal is set for that metric.
    public func progress(for metric: String, value: Double) -> Progress? {
        let target: Double? = switch metric {
        case "StepCount":         Double(dailySteps)
        case "AppleExerciseTime": dailyExerciseMinutes.map(Double.init)
        default:                  nil
        }
        guard let target, target > 0 else { return nil }
        return Progress(metric: metric, target: target, value: value)
    }

    public struct Progress: Sendable, Hashable {
        public let metric: String
        public let target: Double
        public let value: Double

        public var fraction: Double { value / target }
        public var percent: Double { (value / target * 1000).rounded() / 10 }
        public var isMet: Bool { value >= target }
        /// Signed: positive when the goal was passed.
        public var difference: Double { value - target }
    }
}
