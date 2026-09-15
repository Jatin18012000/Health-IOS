import Foundation
import AURACore

/// The compact, pre-computed summary handed to the language model instead of
/// raw data.
///
/// This type is the central design decision of the whole AI layer, so it is
/// worth being blunt about why it exists.
///
/// The naive approach is to put health data in the prompt and ask the model to
/// analyse it. That fails on this dataset in three separate ways:
///
///   - **Volume.** 664,515 samples is roughly 40 million tokens. Four years
///     does not fit in any context window, at any quantisation, on any machine.
///   - **Arithmetic.** Language models are unreliable at exactly the operations
///     that matter here -- averaging a few hundred numbers, computing a
///     percentage change, spotting a correlation. A companion that tells you
///     your resting heart rate improved when it did not is worse than useless;
///     it is misinformation about your own body.
///   - **Latency.** Every token in the prompt is time on the Neural Engine
///     before she says a word.
///
/// So the arithmetic happens in `AURAAnalytics`, deterministically and under
/// test, and the model receives only the finished figures. The model's job is
/// the thing it is genuinely good at: turning a correct, compact set of numbers
/// into warm, specific, plain language.
///
/// A rule of thumb that has to hold: **if a number appears in what she says, it
/// was computed in Swift and passed in here.** She is never asked to derive one.
public struct HealthBrief: Codable, Sendable {
    public struct Figure: Codable, Sendable {
        public let metric: String
        public let label: String
        public let value: Double
        public let unit: String
        /// Percentage change against the comparison window.
        public let changePercent: Double?
        /// Where this sits against the person's own distribution, 0...1.
        /// Personal baselines only -- never population norms, which would turn
        /// a companion into an unlicensed diagnostician.
        public let personalPercentile: Double?
    }

    public struct Observation: Codable, Sendable {
        public let text: String
        /// How strongly the data supports this, 0...1. Weak observations are
        /// passed through but explicitly marked so she can hedge honestly
        /// rather than asserting a coincidence.
        public let confidence: Double
    }

    /// A target and the day's progress against it.
    ///
    /// Carried in the brief rather than left to the UI so that `OutputGuard`
    /// permits her to state it. Without this she is blocked from saying "you
    /// passed your 8,000 step goal" — true, computed, and exactly what a
    /// companion should say.
    public struct GoalProgress: Codable, Sendable {
        public let metric: String
        public let label: String
        public let target: Double
        public let value: Double
        public let percent: Double
        public let isMet: Bool

        public init(metric: String, label: String, target: Double,
                    value: Double, percent: Double, isMet: Bool) {
            self.metric = metric
            self.label = label
            self.target = target
            self.value = value
            self.percent = percent
            self.isMet = isMet
        }
    }

    public let range: DayRange
    public let comparisonRange: DayRange?
    public let figures: [Figure]
    public let goals: [GoalProgress]
    public let observations: [Observation]
    /// Days in `range` with no data, so she can say "I only have four days of
    /// this week" instead of quietly averaging over a gap.
    public let missingDays: Int

    public init(range: DayRange, comparisonRange: DayRange?, figures: [Figure],
                goals: [GoalProgress] = [], observations: [Observation],
                missingDays: Int) {
        self.range = range
        self.comparisonRange = comparisonRange
        self.figures = figures
        self.goals = goals
        self.observations = observations
        self.missingDays = missingDays
    }
}
