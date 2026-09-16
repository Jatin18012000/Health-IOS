import Testing
import Foundation
@testable import AURACore

@Suite("Goals")
struct GoalsTests {

    @Test("the default target is 8,000, not the customary 10,000")
    func defaultTarget() {
        #expect(Goals.default.dailySteps == 8_000)
    }

    @Test("progress is computed against the target, with the surplus signed")
    func progress() {
        // The reference day: 10,171.6 steps against 8,000.
        let p = Goals.default.progress(for: "StepCount", value: 10_171.6)
        #expect(p != nil)
        #expect(p!.isMet)
        #expect(abs(p!.percent - 127.1) < 0.05)
        #expect(abs(p!.difference - 2_171.6) < 0.05)
    }

    @Test("a missed goal reports a negative difference rather than clamping")
    func missedGoal() {
        let p = Goals.default.progress(for: "StepCount", value: 6_340)
        #expect(p?.isMet == false)
        #expect((p?.difference ?? 0) < 0)
    }

    @Test("an unset goal yields no progress rather than a target nobody chose")
    func unsetGoal() {
        // Exercise and sleep goals are nil by default on purpose: showing a
        // ring against an invented target is worse than showing none.
        #expect(Goals.default.progress(for: "AppleExerciseTime", value: 30) == nil)
        #expect(Goals.default.progress(for: "HeartRateVariabilitySDNN", value: 24) == nil)
    }

    @Test("a zero target cannot divide by zero")
    func zeroTarget() {
        var goals = Goals.default
        goals.dailySteps = 0
        #expect(goals.progress(for: "StepCount", value: 5_000) == nil)
    }
}
