import Foundation

/// Resolves the same activity being recorded twice by two devices.
///
/// This is the single most important correctness rule in the ingest path.
/// An iPhone in a pocket and an Apple Watch on a wrist both count the same
/// steps, log the same distance, and estimate the same active energy. Summing
/// every sample double-counts all of it.
///
/// In the reference export this affected 471 day/metric combinations, inflating
/// individual days by as much as 1.9x -- a day whose true figure was ~10,200
/// steps reads as 15,496 if you just add the samples up. Any "trend" computed
/// over mixed single-source and multi-source days is measuring which devices
/// were worn, not the person's activity.
///
/// Apple's own Health app solves this with sample-level source prioritization.
/// AURA does the same thing, explicitly and testably:
///
///   1. Walk sources in trust order -- wrist-worn beats pocket-carried,
///      first-party beats third-party.
///   2. A higher-trust source claims its time intervals outright.
///   3. A lower-trust sample contributes only the fraction of its interval
///      that no higher-trust source already covered, scaled pro-rata by
///      duration.
///
/// So a Watch worn all morning plus an iPhone carried all day yields the
/// Watch's morning and the iPhone's afternoon -- never both for the same hour.
public struct SourceResolver: Sendable {

    /// Lower rank wins. Unrecognised sources sort last rather than being
    /// dropped, so a new device degrades to "trusted least" instead of
    /// vanishing from the data.
    public var ranking: [(pattern: String, rank: Int)]

    public static let `default` = SourceResolver(ranking: [
        ("Apple Watch", 0),
        ("iPhone",      1),
        ("iPad",        2),
        ("FitCloudPro", 3),
        ("NoiseFit",    4),
    ])

    public init(ranking: [(pattern: String, rank: Int)]) {
        self.ranking = ranking
    }

    public func rank(of source: String) -> Int {
        // Apple writes a non-breaking space in "Jatin's Apple Watch", so match
        // on a whitespace-normalised, case-insensitive containment.
        let normalised = source
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .lowercased()
        for entry in ranking where normalised.contains(entry.pattern.lowercased()) {
            return entry.rank
        }
        return .max
    }

    /// The deduplicated total for one day's worth of one cumulative metric.
    public func total(of samples: [Sample]) -> Double {
        let ordered = samples.sorted {
            (rank(of: $0.source), $0.start) < (rank(of: $1.source), $1.start)
        }

        var claimed: [(start: Date, end: Date)] = []
        var total = 0.0

        for sample in ordered {
            let value = sample.value ?? 0
            let span = sample.duration

            guard span > 0 else {
                // An instantaneous cumulative sample: take it whole unless its
                // exact instant already sits inside a claimed interval.
                if !claimed.contains(where: { $0.start <= sample.start && sample.start < $0.end }) {
                    total += value
                    claimed = Self.merge(claimed + [(sample.start, sample.start.addingTimeInterval(1))])
                }
                continue
            }

            let overlap = claimed.reduce(0.0) { acc, c in
                let lo = Swift.max(c.start, sample.start)
                let hi = Swift.min(c.end, sample.end)
                return acc + Swift.max(0, hi.timeIntervalSince(lo))
            }

            let uncovered = Swift.max(0, span - overlap)
            total += value * (uncovered / span)

            if uncovered > 0 {
                claimed = Self.merge(claimed + [(sample.start, sample.end)])
            }
        }

        return total
    }

    static func merge(_ intervals: [(start: Date, end: Date)]) -> [(start: Date, end: Date)] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { $0.start < $1.start }
        var out: [(start: Date, end: Date)] = [sorted[0]]
        for i in sorted.dropFirst() {
            if i.start <= out[out.count - 1].end {
                out[out.count - 1].end = Swift.max(out[out.count - 1].end, i.end)
            } else {
                out.append(i)
            }
        }
        return out
    }
}
