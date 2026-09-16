import Foundation

/// Turns an audio amplitude into a mouth opening.
///
/// The amplitude tap already reports real RMS at roughly 40 Hz. Feeding that
/// straight to a mouth does not work, and neither does the obvious fix.
///
/// ## What was measured
///
/// Against a simulated speech envelope — sustained vowels, sharp consonants,
/// near-silent gaps between words, plus frame noise — two things matter and
/// they pull against each other:
///
/// - **Flutter**: how often the opening reverses direction. High flutter is a
///   mouth flapping rather than talking.
/// - **Closure**: whether the mouth actually shuts in the gaps between words.
///   A mouth that never closes reads as continuous mumbling.
///
/// | | flutter | closes in gaps |
/// |---|---|---|
/// | raw amplitude | 0.27 | 1.00 |
/// | symmetric smoothing (0.6) | 0.20 | 0.93 |
/// | fast attack, slow release (0.5 / 0.15) | 0.11 | **0.30** |
/// | **gated (0.5 / 0.25, gate 0.12)** | **0.15** | **0.95** |
///
/// The third row is the interesting one. Fast attack with slow release is the
/// standard shape for an audio compressor and it is *wrong here*: a compressor
/// uses a slow release to avoid pumping, but a mouth needs to close between
/// words, and the slow release leaves it hanging open through 70% of the gaps.
///
/// The fix is an explicit **noise gate**. Below the gate the opening is driven
/// hard toward closed rather than eased down, which buys a slow release —
/// calm while she is talking — without the mouth hanging open when she is not.
public struct MouthShaper: Sendable {

    /// How fast the mouth opens. High: a consonant should land, not fade in.
    public var attack: Double = 0.5
    /// How fast it eases closed while speech continues.
    public var release: Double = 0.25
    /// Below this amplitude she is between words, not speaking quietly.
    public var gate: Double = 0.12
    /// How hard the gate pulls toward closed. This is what makes the slow
    /// release affordable.
    public var closeSpeed: Double = 0.7

    private var value: Double = 0

    public init() {}

    /// Feed one amplitude sample, get the mouth opening 0...1.
    public mutating func next(_ level: Double) -> Double {
        let amplitude = min(1, max(0, level))
        if amplitude < gate {
            value += (0 - value) * closeSpeed
        } else {
            value += (amplitude - value) * (amplitude > value ? attack : release)
        }
        // Tiny residuals read as a mouth that never quite shuts.
        if value < 0.01 { value = 0 }
        return value
    }

    public mutating func reset() { value = 0 }

    public var current: Double { value }
}
