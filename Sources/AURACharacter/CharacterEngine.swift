import Foundation
import AURACore

/// What AURA is doing right now. The dashboard sets this; the renderer
/// interprets it. Nothing outside this module knows how she is drawn.
public enum CharacterState: Equatable, Sendable {
    case idle
    case greeting
    case thinking
    /// Speaking, with a live 0...1 audio level driving the mouth.
    case speaking(level: Double)
    case listening
    case celebrating
    case resting
}

/// Her emotional colouring, derived from the data rather than chosen at random
/// -- see `MoodResolver`. A recovery score of 92% should not produce a
/// sympathetic expression.
public enum CharacterMood: String, CaseIterable, Sendable, Codable {
    case motivated, calm, concerned, sleepy, proud, neutral
}

/// The renderer contract.
///
/// The whole point of this protocol is that the dashboard never learns which
/// technology is drawing her. Version one is a sprite renderer: the five poses
/// from the design mockups (idle / stretch / cheer / focus / good night) with
/// procedural breathing, blinking, parallax drift and a glow that tracks her
/// speech. Version two swaps in a rigged Live2D Cubism model with real mouth
/// shapes and hair physics -- and changes no code outside this module.
///
/// That seam is the reason to start with sprites rather than waiting on art:
/// the upgrade is a file swap and a new conformer, not a rewrite.
@MainActor
public protocol CharacterRenderer: AnyObject, Sendable {
    /// Drive the visible state. Called at display rate while she speaks, so
    /// implementations must be cheap and must not allocate per frame.
    func apply(state: CharacterState, mood: CharacterMood)

    /// Where she should appear to be looking, in view coordinates.
    /// Sprites approximate this with a small parallax shift; Live2D drives the
    /// real eye and head parameters.
    func look(at point: CGPoint?)

    /// Fired when a pose transition finishes, so scripted sequences can chain.
    var onTransitionComplete: (@Sendable (CharacterState) -> Void)? { get set }
}

/// Picks her mood from the day's actual numbers.
///
/// Deliberately rule-based and deterministic, not model-generated: her
/// expression is a UI affordance that must be stable and instant, and a mood
/// that flickers because a language model sampled differently is worse than no
/// mood at all. The LLM writes the *words*; this picks the *face*.
public struct MoodResolver: Sendable {
    public init() {}

    /// - Parameters:
    ///   - recovery: the recovery score component, 0...100.
    ///   - sleepHours: hours actually asleep.
    ///   - activityPercentile: where today's activity sits against this
    ///     person's own recent history, **0...1** — not progress toward a goal.
    ///     A goal is a number someone picked; a percentile is a fact about them.
    ///   - hour: local hour, 0...23.
    public func mood(recovery: Double?, sleepHours: Double?,
                     activityPercentile: Double?, hour: Int) -> CharacterMood {
        // Order matters: the first matching rule wins, so the things worth
        // interrupting for are checked before the things worth celebrating.
        if hour >= 22 || hour < 5 { return .sleepy }
        if let r = recovery, r < 50 { return .concerned }
        if let s = sleepHours, s < 5 { return .concerned }
        if let p = activityPercentile, p >= 0.9 { return .proud }
        if let r = recovery, r >= 85 { return .motivated }
        if let s = sleepHours, s >= 7 { return .calm }
        return .neutral
    }
}
