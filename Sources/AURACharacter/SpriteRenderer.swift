import Foundation
import AURACore

/// The version-one renderer: pose sprites plus procedural motion.
///
/// Not implemented yet -- this is the shape the M4 milestone fills in.
/// See docs/CHARACTER.md for the pose sheet and the motion budget.
public final class SpriteRenderer: CharacterRenderer, @unchecked Sendable {
    public var onTransitionComplete: (@Sendable (CharacterState) -> Void)?

    public init() {}

    public func apply(state: CharacterState, mood: CharacterMood) {
        // M4: cross-fade to the pose for (state, mood), start the idle breathing
        // and blink timers, and map `speaking(level:)` onto mouth frames.
    }

    public func look(at point: CGPoint?) {
        // M4: parallax offset of the character layers toward `point`.
    }
}
