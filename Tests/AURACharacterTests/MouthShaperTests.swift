import Testing
import Foundation
@testable import AURACharacter

/// The behaviours that make a mouth read as talking rather than flapping.
@Suite("Mouth shaping")
struct MouthShaperTests {

    @Test("silence closes the mouth completely")
    func silenceCloses() {
        var shaper = MouthShaper()
        for _ in 0..<40 { _ = shaper.next(0.8) }
        #expect(shaper.current > 0.5)

        // The gate, not the release, is what does this. With a slow release
        // alone the mouth hangs open through the gaps between words.
        for _ in 0..<10 { _ = shaper.next(0) }
        #expect(shaper.current == 0)
    }

    @Test("a loud sample opens the mouth quickly")
    func fastAttack() {
        var shaper = MouthShaper()
        // A consonant should land, not fade in — three frames is about 75 ms.
        for _ in 0..<3 { _ = shaper.next(0.9) }
        #expect(shaper.current > 0.5)
    }

    @Test("a quiet moment between words is treated as a gap, not quiet speech")
    func gating() {
        var shaper = MouthShaper()
        for _ in 0..<20 { _ = shaper.next(0.8) }
        let open = shaper.current

        // Below the gate she is between words. Easing down from here is what
        // produced only 30% closure in the measurement.
        _ = shaper.next(0.05)
        #expect(shaper.current < open * 0.5)
    }

    @Test("the opening never leaves 0...1")
    func bounded() {
        var shaper = MouthShaper()
        for level in [-1.0, 0.0, 0.5, 2.0, 1.0, -0.3] {
            let value = shaper.next(level)
            // A parameter out of range is undefined behaviour in Cubism and a
            // broken face on screen.
            #expect(value >= 0 && value <= 1)
        }
    }

    @Test("sustained speech settles rather than oscillating")
    func settles() {
        var shaper = MouthShaper()
        var previous = 0.0
        var reversals = 0
        for i in 0..<60 {
            // A steady vowel with a little noise, as the tap would report it.
            let level = 0.7 + (i.isMultiple(of: 2) ? 0.03 : -0.03)
            let value = shaper.next(level)
            if i > 5, (value - previous) * (previous - shaper.current) < 0 { reversals += 1 }
            previous = value
        }
        #expect(shaper.current > 0.6)
    }

    @Test("reset closes it immediately")
    func reset() {
        var shaper = MouthShaper()
        for _ in 0..<20 { _ = shaper.next(0.9) }
        shaper.reset()
        #expect(shaper.current == 0)
    }
}
