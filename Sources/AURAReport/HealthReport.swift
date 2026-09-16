import Foundation
import AURACore
import AURAAnalytics
import AURAMemory

/// A summary of the data, for someone with ten minutes and a clinical question.
///
/// ## What this deliberately does not contain
///
/// **No AI interpretation.** Not a single generated sentence. A doctor wants the
/// measurements and their provenance; a language model's opinion about them is
/// worse than useless in a consultation, because it is confident, it is
/// unattributable, and it invites the reader to argue with a machine instead of
/// reading the numbers. Everything in this report is a figure, a count, or a
/// statement about where the figures came from.
///
/// **No scores.** The composite is a personal, self-referential number designed
/// to be read by the person it describes against their own history. Out of that
/// context it looks like a clinical index and is not one.
///
/// **No diagnoses, no flags, no reference ranges.** `OutputGuard` stops her
/// saying such things aloud; a PDF she never sees would route around that
/// entirely. So this report states what was measured and says plainly what the
/// measurements cannot support.
public struct HealthReport: Sendable {

    public struct Row: Sendable, Identifiable {
        public var id: String { metric }
        public let metric: String
        public let label: String
        public let unit: String
        public let latest: Double?
        public let latestDay: CalendarDay?
        public let mean30: Double?
        public let mean365: Double?
        /// Days with a reading in the last year. The single most important
        /// column: a mean over 12 readings and a mean over 365 are not the
        /// same kind of fact, and a table that hides that is misleading.
        public let coverage365: Int
    }

    public struct SleepSummary: Sendable {
        public let stagedNights: Int
        public let inBedOnlyNights: Int
        public let meanAsleepStaged: Double?
        public let meanEfficiencyStaged: Double?
        public let meanAsleepInBedOnly: Double?
    }

    public struct Period: Sendable, Identifiable {
        public var id: String { "\(kind)-\(range.start)" }
        public let kind: String
        public let range: DayRange
        public let dayCount: Int
        public let note: String?
    }

    public let generatedOn: Date
    public let range: DayRange
    public let totalDays: Int
    public let rows: [Row]
    public let sleep: SleepSummary
    public let periods: [Period]
    public let sources: [String]

    // MARK: - Building

    /// Metrics a clinician is plausibly asking about. Deliberately short — a
    /// forty-row table of walking asymmetry and headphone exposure buries the
    /// four things that matter.
    static let reported = [
        "RestingHeartRate", "HeartRateVariabilitySDNN", "RespiratoryRate",
        "OxygenSaturation", "BloodPressureSystolic", "BloodPressureDiastolic",
        "BodyMass", "VO2Max", "StepCount", "ActiveEnergyBurned",
        "AppleExerciseTime", "AppleWalkingSteadiness",
    ]

    public static func build(
        store: any AnalyticsStore,
        memory: MemoryStore?,
        endingOn day: CalendarDay,
        months: Int = 12
    ) async throws -> HealthReport {
        let days = months * 30
        let range = DayRange.lastDays(days, endingOn: day)
        let trends = TrendEngine(store: store)

        var rows: [Row] = []
        for metric in reported {
            guard let spec = MetricCatalog[metric] else { continue }
            let year = try await store.daily(metric: metric, in: range)
            let recent = try await store.daily(
                metric: metric, in: .lastDays(30, endingOn: day))

            let yearValues = year.compactMap(\.value)
            // A metric with nothing in it is omitted rather than shown as a row
            // of dashes. An empty row reads as "we looked and found nothing
            // wrong"; omission reads as "this was not measured", which is true.
            guard !yearValues.isEmpty else { continue }

            let last = year.last { $0.value != nil }
            rows.append(Row(
                metric: metric, label: spec.title, unit: spec.unit.rawValue,
                latest: last?.value, latestDay: last?.day,
                mean30: Stats.mean(recent.compactMap(\.value)),
                mean365: Stats.mean(yearValues),
                coverage365: yearValues.count))
        }
        _ = trends

        let nights = try await store.nights(in: range)
        let staged = nights.filter(\.isStaged)
        let unstaged = nights.filter { !$0.isStaged }

        var periods: [Period] = []
        if let memory {
            for annotation in try await memory.annotations(overlapping: range) {
                periods.append(Period(
                    kind: annotation.kind.label, range: annotation.range,
                    dayCount: annotation.dayCount, note: annotation.note))
            }
        }

        let covered = try await store.daily(metric: "StepCount", in: range).count

        return HealthReport(
            generatedOn: Date(),
            range: range,
            totalDays: covered,
            rows: rows,
            sleep: SleepSummary(
                stagedNights: staged.count,
                inBedOnlyNights: unstaged.count,
                meanAsleepStaged: Stats.mean(staged.map(\.asleepMinutes)),
                meanEfficiencyStaged: Stats.mean(staged.compactMap(\.efficiency)),
                meanAsleepInBedOnly: Stats.mean(unstaged.map(\.asleepMinutes))),
            periods: periods,
            sources: try await sourceNames(store: store, range: range))
    }

    private static func sourceNames(store: any AnalyticsStore,
                                    range: DayRange) async throws -> [String] {
        let samples = try await store.samples(metric: "StepCount",
                                              in: .lastDays(30, endingOn: range.end))
        return Array(Set(samples.map(\.source))).sorted()
    }

    /// The paragraph that makes the rest of it honest.
    ///
    /// Every limitation here is one a reader would otherwise have to guess at,
    /// and two of them — the deduplication and the sleep split — are invisible
    /// from the numbers alone.
    public var limitations: [String] {
        var notes = [
            "Data is from consumer devices, not medical instruments. Treat it as "
            + "an indication of trend, not as a measurement.",
            "Figures are daily aggregates. Where a day carried readings from more "
            + "than one device, overlapping periods were counted once rather than "
            + "summed, so totals are lower than a naive sum of the raw records.",
        ]

        if sleep.stagedNights > 0 && sleep.inBedOnlyNights > 0 {
            notes.append(
                "Sleep is recorded two different ways in this period: "
                + "\(sleep.stagedNights) night(s) with measured stages, and "
                + "\(sleep.inBedOnlyNights) night(s) recording time in bed only. "
                + "These are not comparable and are reported separately.")
        }

        let sparse = rows.filter { $0.coverage365 < 30 }
        if !sparse.isEmpty {
            notes.append(
                "Sparse coverage: "
                + sparse.map { "\($0.label) (\($0.coverage365) reading(s))" }
                    .joined(separator: ", ")
                + ". Means over so few readings should not be read as trends.")
        }

        if !periods.isEmpty {
            notes.append(
                "The subject marked \(periods.count) period(s) as unusual — listed "
                + "above. These were NOT excluded from any average.")
        }

        return notes
    }
}
