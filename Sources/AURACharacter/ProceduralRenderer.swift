import SwiftUI
import AURACore

/// The version-one renderer: one illustration, driven entirely procedurally.
///
/// Deliberately **not** a pose sheet. The five poses in the original design were
/// AI-generated and are not quite the same character — jacket detailing, hair
/// fall and face proportions drift between them, which is inherent to generation
/// rather than a prompt problem. Cutting between them reads as a glitch, and the
/// drift is far more visible in motion than side by side.
///
/// So: one image, never still. Breathing, sway, blink, parallax, and a mouth and
/// rim light driven by the live audio level.
///
/// Every signal here maps one-to-one onto a Cubism parameter, which is the point
/// — when the Live2D rig lands the driving code barely changes:
///
/// | here | Live2D |
/// |---|---|
/// | `sway` | `ParamAngleX/Y/Z` |
/// | `mouthOpen` | `ParamMouthOpenY` |
/// | `eyeOpen` | `ParamEyeLOpen` / `ParamEyeROpen` |
/// | `gaze` | `ParamEyeBallX/Y` |
/// | `breath` | `ParamBreath` |
@Observable
@MainActor
public final class ProceduralRenderer: CharacterRenderer {

    // MARK: Driven values, 0...1 unless noted

    public private(set) var breath: Double = 0
    public private(set) var sway: CGSize = .zero
    public private(set) var eyeOpen: Double = 1
    public private(set) var mouthOpen: Double = 0
    public private(set) var gaze: CGSize = .zero
    public private(set) var glow: Double = 0.25

    public private(set) var state: CharacterState = .idle
    public private(set) var mood: CharacterMood = .neutral

    public var onTransitionComplete: (@Sendable (CharacterState) -> Void)?

    // MARK: Timing
    //
    // Independent periods with jitter, and deliberately not multiples of each
    // other. Perfectly periodic motion is the tell that something is a loop;
    // two cycles that never quite line up read as alive.

    private var clock: TimeInterval = 0
    private var breathPeriod: Double = 5.0
    private var swayPeriod: Double = 8.3
    private var nextBlink: TimeInterval = 4
    private var blinkStarted: TimeInterval?
    private var ticker: Task<Void, Never>?

    public init() {}

    public func start() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            // 60 Hz. The stage must never compete with the language model for
            // the GPU — if she stutters while she thinks, she stops being a
            // companion and becomes a progress indicator.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                await self?.tick(1.0 / 60.0)
            }
        }
    }

    public func stop() {
        ticker?.cancel()
        ticker = nil
    }

    // MARK: CharacterRenderer

    public func apply(state: CharacterState, mood: CharacterMood) {
        self.state = state
        self.mood = mood

        if case .speaking(let level) = state {
            // Straight from the audio tap. A mouth on a timer reads as a
            // cartoon playing over audio; a mouth tracking the waveform reads
            // as someone talking. This is the single highest-leverage detail
            // in the whole character.
            mouthOpen = min(1, max(0, level))
            glow = 0.3 + level * 0.5
        } else {
            mouthOpen = 0
            glow = mood == .sleepy ? 0.15 : 0.25
        }

        // Resting differs from idle in amplitude, not in kind.
        breathPeriod = (state == .resting || mood == .sleepy) ? 6.5 : 5.0
        onTransitionComplete?(state)
    }

    public func look(at point: CGPoint?) {
        guard let point else {
            gaze = .zero
            return
        }
        // Clamped hard: a character whose eyes track a cursor across a 1440pt
        // window looks possessed. A few degrees is all presence needs.
        gaze = CGSize(width: max(-1, min(1, point.x)) * 0.4,
                      height: max(-1, min(1, point.y)) * 0.25)
    }

    // MARK: Motion

    private func tick(_ dt: TimeInterval) {
        clock += dt

        breath = sin(clock * 2 * .pi / breathPeriod)
        sway = CGSize(width: sin(clock * 2 * .pi / swayPeriod) * 3,
                      height: cos(clock * 2 * .pi / (swayPeriod * 1.37)) * 2)

        if let started = blinkStarted {
            let t = (clock - started) / 0.12
            if t >= 1 {
                blinkStarted = nil
                eyeOpen = 1
                // Randomised interval. A blink every four seconds exactly is
                // more unsettling than no blink at all.
                nextBlink = clock + Double.random(in: 3...7)
            } else {
                // Down and back up over the blink's duration.
                eyeOpen = abs(t - 0.5) * 2
            }
        } else if clock >= nextBlink && state != .resting {
            blinkStarted = clock
        }
    }

    /// Mood changes the light on the same image, never the image.
    ///
    /// This is what makes one illustration sufficient: concerned is a cooler rim
    /// and a slight forward lean, proud is warmer and lifted. Sidesteps the
    /// character-drift problem entirely, and is more convincing than a hard cut
    /// between two drawings would be.
    public var moodTint: Color {
        switch mood {
        case .motivated: Color(red: 0.30, green: 0.95, blue: 0.65)
        case .calm:      Color(red: 0.20, green: 0.85, blue: 1.00)
        case .concerned: Color(red: 1.00, green: 0.75, blue: 0.25)
        case .sleepy:    Color(red: 0.55, green: 0.40, blue: 1.00)
        case .proud:     Color(red: 1.00, green: 0.30, blue: 0.75)
        case .neutral:   Color(red: 0.55, green: 0.40, blue: 1.00)
        }
    }

    public var postureLean: Double {
        switch mood {
        case .concerned: 2.0
        case .proud:     -2.5
        case .sleepy:    3.0
        default:         0
        }
    }
}
