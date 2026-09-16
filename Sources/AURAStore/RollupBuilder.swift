import Foundation
import GRDB
import AURACore

/// Rebuilds `daily_metrics` and `sleep_nights` from stored samples.
///
/// Separate from the store because it is pure aggregation with one job, and
/// because it is the piece most likely to change: every new aggregation rule
/// lands here and nowhere else.
///
/// Mirrors the rollup half of `tools/reference_pipeline.py`. `tools/conformance.py`
/// is what holds the two together.
struct RollupBuilder {

    let resolver: SourceResolver

    /// A sleep session is attributed to the night it *ends*. Anything ending
    /// before this hour rolls back to the previous calendar day, so a session
    /// finishing at 07:00 on the 12th belongs to the night of the 11th.
    static let sleepDayCutoffHour = 18

    func rebuild(_ db: Database, range: DayRange) throws {
        let (from, to) = SQLiteHealthStore.bounds(of: range)

        // Rebuild rather than patch: an aggregation rule change must be able to
        // restate history, and a partial update is how a rollup silently drifts
        // out of agreement with the samples underneath it.
        try db.execute(sql: "DELETE FROM daily_metrics WHERE day BETWEEN ? AND ?",
                       arguments: [range.start.description, range.end.description])
        try db.execute(sql: "DELETE FROM sleep_nights WHERE night_of BETWEEN ? AND ?",
                       arguments: [range.start.description, range.end.description])

        let rows = try Row.fetchAll(db, sql: """
            SELECT m.identifier, s.value, s.category, so.name, s.start_at, s.end_at
            FROM samples s
            JOIN metrics m  ON m.id  = s.metric_id
            JOIN sources so ON so.id = s.source_id
            WHERE s.start_at >= ? AND s.start_at < ?
            ORDER BY s.start_at
            """, arguments: [from, to])

        var byDay: [CalendarDay: [String: [Sample]]] = [:]
        var sleep: [Sample] = []

        for row in rows {
            let sample = Sample(
                metric: row[0], value: row[1], category: row[2], source: row[3],
                start: Date(timeIntervalSince1970: row[4]),
                end: Date(timeIntervalSince1970: row[5]))

            if sample.metric == "SleepAnalysis" {
                sleep.append(sample)
            } else {
                byDay[CalendarDay(sample.start), default: [:]][sample.metric, default: []].append(sample)
            }
        }

        for (day, metrics) in byDay {
            for (identifier, samples) in metrics {
                guard let metric = MetricCatalog[identifier],
                      let rollup = aggregate(metric: metric, samples: samples)
                else { continue }

                try db.execute(sql: """
                    INSERT OR REPLACE INTO daily_metrics
                    (day, identifier, domain, unit, value, value_min, value_max,
                     sample_count, source_count, method)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        day.description, identifier, metric.domain.rawValue,
                        metric.unit.rawValue, rollup.value, rollup.min, rollup.max,
                        samples.count, Set(samples.map(\.source)).count, rollup.method])
            }
        }

        try rebuildSleep(db, samples: sleep)
    }

    // MARK: - Daily aggregation

    private struct Rollup {
        var value: Double?
        var min: Double?
        var max: Double?
        var method: String
    }

    private func aggregate(metric: Metric, samples: [Sample]) -> Rollup? {
        let values = samples.compactMap(\.value)
        let sources = Set(samples.map(\.source))

        switch metric.aggregation {
        case .sum:
            // Only cumulative metrics from more than one device need resolving.
            // Everything else is a plain sum, and saying so in `method` keeps
            // the distinction visible in the stored row.
            if metric.isCumulative && sources.count > 1 {
                return Rollup(value: resolver.total(of: samples), method: "sum/deduped")
            }
            return Rollup(value: values.reduce(0, +), method: "sum")

        case .mean:
            guard !values.isEmpty else { return nil }
            return Rollup(value: values.reduce(0, +) / Double(values.count), method: "mean")

        case .minMax:
            guard !values.isEmpty else { return nil }
            return Rollup(value: values.reduce(0, +) / Double(values.count),
                          min: values.min(), max: values.max(), method: "minmax")

        case .last:
            guard let latest = samples.max(by: { $0.start < $1.start }) else { return nil }
            return Rollup(value: latest.value, method: "last")

        case .count:
            // A stand hour counts only if it was actually stood.
            if metric.id == "AppleStandHour" {
                let stood = samples.filter { $0.category == "HKCategoryValueAppleStandHourStood" }
                return Rollup(value: Double(stood.count), method: "count/stood")
            }
            return Rollup(value: Double(samples.count), method: "count")

        case .interval:
            return nil   // sleep is reconstructed separately
        }
    }

    // MARK: - Sleep

    private func rebuildSleep(_ db: Database, samples: [Sample]) throws {
        var nights: [CalendarDay: [Sample]] = [:]
        for sample in samples {
            nights[Self.night(of: sample.end), default: []].append(sample)
        }

        for (night, session) in nights {
            var minutes: [String: Double] = [:]
            for sample in session {
                let stage = Self.stage(from: sample.category)
                minutes[stage, default: 0] += sample.duration / 60
            }

            let core = minutes["AsleepCore"] ?? 0
            let deep = minutes["AsleepDeep"] ?? 0
            let rem = minutes["AsleepREM"] ?? 0
            let unspecified = minutes["AsleepUnspecified"] ?? 0
            let awake = minutes["Awake"] ?? 0
            let staged = (core + deep + rem) > 0

            // Two eras, and they are not the same quantity. A staged night knows
            // you were asleep; an in-bed-only night knows the phone thought you
            // were in bed. Blending them charts a hardware upgrade as a trend.
            let asleep: Double
            if staged {
                asleep = core + deep + rem + unspecified
            } else if unspecified > 0 {
                asleep = unspecified
            } else {
                asleep = Self.unionMinutes(session.filter { Self.stage(from: $0.category) == "InBed" })
            }

            // The union, never the sum: the InBed interval contains every stage
            // inside it, so adding them counts the same minutes several times.
            let inBed = Self.unionMinutes(session)
            let starts = session.map(\.start)
            let ends = session.map(\.end)

            try db.execute(sql: """
                INSERT OR REPLACE INTO sleep_nights
                (night_of, in_bed_start, in_bed_end, in_bed_min, asleep_min,
                 core_min, deep_min, rem_min, awake_min, efficiency, staged, sources)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    night.description,
                    starts.min().map { Int($0.timeIntervalSince1970) },
                    ends.max().map { Int($0.timeIntervalSince1970) },
                    inBed.rounded(to: 1), asleep.rounded(to: 1),
                    core.rounded(to: 1), deep.rounded(to: 1),
                    rem.rounded(to: 1), awake.rounded(to: 1),
                    inBed > 0 ? (asleep / inBed * 100).rounded(to: 1) : nil,
                    staged ? 1 : 0,
                    Set(session.map(\.source)).sorted().joined(separator: ",")])
        }
    }

    static func night(of end: Date, calendar: Calendar = .current) -> CalendarDay {
        let day = CalendarDay(end, in: calendar)
        let hour = calendar.component(.hour, from: end)
        return hour < sleepDayCutoffHour ? day.adding(days: -1, in: calendar) : day
    }

    static func stage(from category: String?) -> String {
        (category ?? "").replacingOccurrences(
            of: "HKCategoryValueSleepAnalysis", with: "")
    }

    /// Total minutes covered by these samples, counting overlapping time once.
    static func unionMinutes(_ samples: [Sample]) -> Double {
        let merged = SourceResolver.merge(samples.map { ($0.start, $0.end) })
        return merged.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 60
    }
}

private extension Double {
    func rounded(to places: Int) -> Double {
        let f = pow(10.0, Double(places))
        return (self * f).rounded() / f
    }
}
