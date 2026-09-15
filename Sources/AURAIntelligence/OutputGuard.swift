import Foundation
import AURACore

/// Checks generated text before it is ever spoken.
///
/// Two distinct failure modes, and they are not the same problem:
///
/// **Clinical overreach** — diagnosis, prescription, "you should stop taking".
/// She observes and encourages; she does not practise medicine.
///
/// **Fabricated figures** — a number in the output that was not in the brief.
/// This is the dangerous one, because it is plausible, specific and wrong, and
/// it is about the reader's own body where they have no way to check it.
///
/// The second is the harder problem, because correct prose legitimately
/// contains numbers that are *not literally* in the brief: 455 minutes becomes
/// "7h 35m", 0.954 becomes "95%". So the guard has to recognise honest
/// derivations while still rejecting invention.
///
/// Ported from `tools/output_guard.py`, where the rules were built against
/// worked examples first. Two bugs found there are worth not reintroducing:
/// a *relative* tolerance turned every free number into a wide accepting band
/// (at 5%, "60" alone authorised anything from 57 to 63, letting a fabricated
/// resting heart rate of 58 bpm through), and applying the minutes-to-hours
/// derivation to non-durations meant a score component of 91.4 quietly
/// authorised "31".
public struct OutputGuard: Sendable {

    public init() {}

    public enum Verdict: Sendable, Equatable {
        case allow
        case rewrite(reason: String)
        case block(reason: String)
    }

    public struct Problem: Sendable, Equatable {
        public enum Kind: String, Sendable { case clinical, fabricatedFigure }
        public let kind: Kind
        public let detail: String
        public let evidence: String
    }

    /// What kind of quantity a value is, which decides how it may be reworded.
    ///
    /// A derivation is only honest if the source value is actually the kind of
    /// quantity it claims to convert.
    enum Quantity {
        case durationMinutes, fraction, percent, count, plain
    }

    /// Numbers needing no source: small counts, ordinals, days of the month,
    /// and the clock. Matched **exactly** — see `tolerance`.
    static let freeNumbers: Set<Double> = {
        var set = Set((0...31).map(Double.init))
        set.formUnion([60, 90, 100, 180, 365, 1000])
        return set
    }()

    /// Absorbs float noise only. Rounding is already covered by `derivations`.
    static let tolerance = 0.051

    /// Language out of bounds regardless of context.
    ///
    /// Deliberately short. A long list of banned words produces a companion
    /// that cannot discuss health at all, which is its own failure.
    static let clinicalPatterns: [(pattern: String, reason: String)] = [
        (#"\byou (?:have|may have|might have|likely have)\b"#, "suggests a diagnosis"),
        (#"\b(?:diagnos|prognos)\w*\b"#, "diagnostic language"),
        (#"\b(?:prescrib|dosage|dose of)\w*\b"#, "prescriptive language"),
        (#"\b(?:stop|start|increase|reduce) (?:taking|your) (?:medication|dose|meds)\b"#,
         "medication advice"),
        (#"\bthis (?:is|could be) (?:a sign of|symptomatic of|indicative of)\b"#,
         "diagnostic inference"),
    ]

    /// Metrics genuinely measured in minutes, and therefore the only ones that
    /// may legitimately be restated as hours and minutes.
    static let minuteValued: Set<String> = [
        "AppleExerciseTime", "AppleStandTime", "TimeInDaylight", "MindfulSession",
    ]

    // MARK: - Checking

    public func check(_ output: String, against brief: HealthBrief) -> Verdict {
        let problems = problems(in: output, against: brief)
        guard let first = problems.first else { return .allow }

        // Clinical overreach is blocked outright; a fabricated figure is a
        // rewrite, because the surrounding prose is usually fine and worth
        // keeping once the invented number is gone.
        if problems.contains(where: { $0.kind == .clinical }) {
            return .block(reason: first.detail)
        }
        return .rewrite(reason: "stated a figure that was not computed: \(first.detail)")
    }

    public func problems(in output: String, against brief: HealthBrief) -> [Problem] {
        var found: [Problem] = []

        for (pattern, reason) in Self.clinicalPatterns {
            if let range = output.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                found.append(Problem(kind: .clinical, detail: reason,
                                     evidence: String(output[range])))
            }
        }

        let allowed = Self.allowedNumbers(in: brief)
        for match in Self.numerals(in: output) {
            guard let value = Double(match.text.replacingOccurrences(of: ",", with: ""))
            else { continue }
            if allowed.contains(where: { abs(value - $0) <= Self.tolerance }) { continue }
            found.append(Problem(kind: .fabricatedFigure, detail: match.text,
                                 evidence: match.context))
        }

        return found
    }

    // MARK: - Allowed numbers

    static func allowedNumbers(in brief: HealthBrief) -> Set<Double> {
        var allowed = freeNumbers

        func add(_ value: Double?, _ kind: Quantity) {
            guard let value else { return }
            allowed.formUnion(derivations(of: abs(value), as: kind))
        }

        for figure in brief.figures {
            let kind: Quantity = minuteValued.contains(figure.metric) ? .durationMinutes : .count
            add(figure.value, kind)
            add(figure.changePercent, .percent)
            add(figure.personalPercentile, .fraction)
        }

        // Goals and progress against them. Without this the guard blocks her
        // from saying "you passed your 8,000 step goal", which is true and
        // computed — a safety check that rejects honest statements is a defect,
        // not caution.
        for goal in brief.goals {
            add(goal.target, .count)
            add(goal.value, .count)
            add(goal.percent, .percent)
            add(abs(goal.value - goal.target), .count)
        }

        // Coefficients and sample sizes already quoted in the observations —
        // she may repeat what the analysis handed her.
        for observation in brief.observations {
            for match in numerals(in: observation.text) {
                if let v = Double(match.text.replacingOccurrences(of: ",", with: "")) {
                    add(abs(v), .plain)
                }
            }
        }

        let year = brief.range.end.year
        allowed.formUnion(((year - 10)...(year + 1)).map(Double.init))
        return allowed
    }

    /// Every honest way a figure can appear in prose. Anything here is a
    /// formatting or unit choice a writer would make, not a new claim.
    static func derivations(of value: Double, as kind: Quantity) -> Set<Double> {
        var out: Set<Double> = [value, value.rounded(), (value * 10).rounded() / 10]

        switch kind {
        case .durationMinutes:
            if value >= 60 {
                out.insert((value / 60).rounded(.down))
                out.insert(value.truncatingRemainder(dividingBy: 60).rounded())
                out.insert(((value / 60) * 10).rounded() / 10)
                out.insert(((value / 60) * 100).rounded() / 100)
            }
        case .fraction:
            out.insert((value * 100).rounded())
            out.insert((value * 1000).rounded() / 10)
        case .percent:
            out.insert((value).rounded() / 100)
        case .count:
            if value >= 1000 {
                out.insert((value / 100).rounded() / 10)
                out.insert((value / 1000).rounded())
            }
        case .plain:
            break
        }
        return out
    }

    // MARK: - Scanning

    struct NumeralMatch { let text: String; let context: String }

    static func numerals(in text: String) -> [NumeralMatch] {
        guard let regex = try? NSRegularExpression(pattern: #"\d+(?:[.,]\d+)?"#)
        else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { match in
                let lo = max(0, match.range.location - 36)
                let hi = min(ns.length, match.range.location + match.range.length + 36)
                return NumeralMatch(
                    text: ns.substring(with: match.range),
                    context: ns.substring(with: NSRange(location: lo, length: hi - lo))
                        .trimmingCharacters(in: .whitespacesAndNewlines))
            }
    }
}
