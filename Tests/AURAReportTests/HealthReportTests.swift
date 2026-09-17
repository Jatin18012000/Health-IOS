import Testing
import Foundation
import AURACore
import AURAAnalytics
import AURAMemory
@testable import AURAReport

/// Every expected value here was computed by hand, not copied from a run.
/// A test that records what the code currently does is worth nothing.
///
/// What these are really guarding: this report is the one thing in the project
/// that leaves the machine and lands in someone else's hands, and its failure
/// mode is not a crash. It is a plausible-looking table that a clinician reads
/// wrong — a mean over three readings presented like a mean over three hundred,
/// or staged and in-bed-only sleep averaged together into a number that
/// describes neither.
@Suite("Health report")
struct HealthReportTests {

    // MARK: A store that returns exactly what a test puts in it

    private struct FakeStore: AnalyticsStore {
        var dailyRows: [String: [DailyMetric]] = [:]
        var nightRows: [SleepNight] = []
        var sampleRows: [Sample] = []

        func daily(metric: String, in range: DayRange) async throws -> [DailyMetric] {
            (dailyRows[metric] ?? [])
                .filter { $0.day >= range.start && $0.day <= range.end }
        }

        func daily(domain: MetricDomain, on day: CalendarDay) async throws -> [DailyMetric] {
            []
        }

        func nights(in range: DayRange) async throws -> [SleepNight] {
            nightRows.filter { $0.nightOf >= range.start && $0.nightOf <= range.end }
        }

        func samples(metric: String, in range: DayRange) async throws -> [Sample] {
            sampleRows
        }

        func availableRange() async throws -> DayRange? {
            DayRange(start: HealthReportTests.endDay.adding(days: -400),
                     end: HealthReportTests.endDay)
        }
    }

    /// A fixed day, so nothing here depends on when the suite runs.
    static let endDay = CalendarDay(year: 2025, month: 3, day: 31)

    private static func row(_ metric: String, _ day: CalendarDay,
                            _ value: Double?) -> DailyMetric {
        DailyMetric(day: day, metric: metric,
                    domain: MetricCatalog[metric]?.domain ?? .activity,
                    unit: MetricCatalog[metric]?.unit ?? .count,
                    value: value, sampleCount: 1, sourceCount: 1)
    }

    private static func night(_ day: CalendarDay, asleep: Double,
                              efficiency: Double?, staged: Bool) -> SleepNight {
        SleepNight(nightOf: day, inBedStart: Date(), inBedEnd: Date(),
                   inBedMinutes: asleep + 30, asleepMinutes: asleep,
                   coreMinutes: staged ? asleep * 0.5 : 0,
                   deepMinutes: staged ? asleep * 0.2 : 0,
                   remMinutes: staged ? asleep * 0.3 : 0,
                   awakeMinutes: 30, efficiency: efficiency,
                   isStaged: staged, sources: ["Apple Watch"])
    }

    /// 40 days of resting heart rate: 60 bpm for the last 30, 50 bpm for the
    /// ten before that. Chosen so the 30-day and 365-day means must differ.
    private static func heartRateStore() -> FakeStore {
        var rows: [DailyMetric] = []
        for offset in stride(from: -39, through: 0, by: 1) {
            let day = endDay.adding(days: offset)
            rows.append(Self.row("RestingHeartRate", day, offset >= -29 ? 60 : 50))
        }
        var store = FakeStore()
        store.dailyRows["RestingHeartRate"] = rows
        return store
    }

    // MARK: The columns

    @Test("the 30-day and 365-day means are over different windows")
    func meansUseDifferentWindows() async throws {
        let report = try await HealthReport.build(
            store: Self.heartRateStore(), memory: nil, endingOn: Self.endDay)

        let hr = try #require(report.rows.first { $0.metric == "RestingHeartRate" })
        // 30 days at 60.
        #expect(hr.mean30 == 60)
        // (30 x 60 + 10 x 50) / 40 = 2300 / 40.
        #expect(hr.mean365 == 57.5)
    }

    @Test("coverage counts days with a reading, not days in the range")
    func coverageCountsReadings() async throws {
        let report = try await HealthReport.build(
            store: Self.heartRateStore(), memory: nil, endingOn: Self.endDay)

        let hr = try #require(report.rows.first { $0.metric == "RestingHeartRate" })
        // 40 readings inside a 360-day window. This column is the whole reason
        // a mean in this table can be read safely: without it, 40 readings and
        // 360 readings produce identically confident-looking numbers.
        #expect(hr.coverage365 == 40)
    }

    @Test("latest is the most recent reading that actually has a value")
    func latestSkipsEmptyDays() async throws {
        var store = Self.heartRateStore()
        // A row exists for the final two days but carries no value — a day the
        // device was worn but recorded nothing. Taking the last *row* rather
        // than the last *value* would report an empty latest reading.
        store.dailyRows["RestingHeartRate"]?.append(
            Self.row("RestingHeartRate", Self.endDay.adding(days: 1), nil))
        store.dailyRows["RestingHeartRate"]?.append(
            Self.row("RestingHeartRate", Self.endDay.adding(days: 2), nil))

        let report = try await HealthReport.build(
            store: store, memory: nil, endingOn: Self.endDay.adding(days: 2))

        let hr = try #require(report.rows.first { $0.metric == "RestingHeartRate" })
        #expect(hr.latest == 60)
        #expect(hr.latestDay == Self.endDay)
    }

    @Test("a metric with no readings is omitted, not shown as an empty row")
    func emptyMetricsAreOmitted() async throws {
        let report = try await HealthReport.build(
            store: Self.heartRateStore(), memory: nil, endingOn: Self.endDay)

        // An empty row reads as "we looked and found nothing wrong"; omission
        // reads as "this was not measured", which is the true statement.
        #expect(report.rows.contains { $0.metric == "RestingHeartRate" })
        #expect(!report.rows.contains { $0.metric == "BodyMass" })
        #expect(!report.rows.contains { $0.metric == "VO2Max" })
    }

    @Test("rows keep the clinical order, not the order data arrived in")
    func rowOrderIsStable() async throws {
        var store = FakeStore()
        // Inserted with steps first; the report must still lead with the vitals.
        store.dailyRows["StepCount"] = [Self.row("StepCount", Self.endDay, 9000)]
        store.dailyRows["RestingHeartRate"] =
            [Self.row("RestingHeartRate", Self.endDay, 58)]

        let report = try await HealthReport.build(
            store: store, memory: nil, endingOn: Self.endDay)

        let order = report.rows.map(\.metric)
        let heart = try #require(order.firstIndex(of: "RestingHeartRate"))
        let steps = try #require(order.firstIndex(of: "StepCount"))
        #expect(heart < steps)
    }

    // MARK: Sleep — the invariant that matters most here

    @Test("staged and in-bed-only nights are counted and averaged apart")
    func sleepKindsStaySeparate() async throws {
        var store = Self.heartRateStore()
        store.nightRows = [
            Self.night(Self.endDay.adding(days: -4), asleep: 400,
                       efficiency: 0.90, staged: true),
            Self.night(Self.endDay.adding(days: -3), asleep: 420,
                       efficiency: 0.92, staged: true),
            Self.night(Self.endDay.adding(days: -2), asleep: 440,
                       efficiency: 0.94, staged: true),
            Self.night(Self.endDay.adding(days: -1), asleep: 300,
                       efficiency: nil, staged: false),
            Self.night(Self.endDay, asleep: 360, efficiency: nil, staged: false),
        ]

        let report = try await HealthReport.build(
            store: store, memory: nil, endingOn: Self.endDay)

        #expect(report.sleep.stagedNights == 3)
        #expect(report.sleep.inBedOnlyNights == 2)
        // (400 + 420 + 440) / 3
        #expect(report.sleep.meanAsleepStaged == 420)
        // (300 + 360) / 2 — and emphatically NOT pooled with the staged nights,
        // which would give (400+420+440+300+360)/5 = 384, a number describing
        // neither kind of night.
        #expect(report.sleep.meanAsleepInBedOnly == 330)
        // (0.90 + 0.92 + 0.94) / 3. The in-bed-only nights have no efficiency
        // at all and must not be counted as zeroes.
        #expect(report.sleep.meanEfficiencyStaged == 0.92)
    }

    // MARK: Limitations — the paragraph that makes the table honest

    @Test("the sleep split is disclosed only when both kinds are present")
    func sleepSplitDisclosure() async throws {
        var store = Self.heartRateStore()
        store.nightRows = [
            Self.night(Self.endDay, asleep: 400, efficiency: 0.9, staged: true),
        ]
        let stagedOnly = try await HealthReport.build(
            store: store, memory: nil, endingOn: Self.endDay)
        #expect(!stagedOnly.limitations.contains { $0.contains("two different ways") })

        store.nightRows.append(
            Self.night(Self.endDay.adding(days: -1), asleep: 300,
                       efficiency: nil, staged: false))
        let mixed = try await HealthReport.build(
            store: store, memory: nil, endingOn: Self.endDay)
        #expect(mixed.limitations.contains { $0.contains("two different ways") })
    }

    @Test("sparse metrics are named, with their reading count")
    func sparseCoverageIsNamed() async throws {
        var store = Self.heartRateStore()
        // Three readings of body mass across a year. A mean of three is not a
        // trend, and the table cannot say so by itself.
        store.dailyRows["BodyMass"] = [
            Self.row("BodyMass", Self.endDay.adding(days: -200), 70),
            Self.row("BodyMass", Self.endDay.adding(days: -100), 71),
            Self.row("BodyMass", Self.endDay, 72),
        ]

        let report = try await HealthReport.build(
            store: store, memory: nil, endingOn: Self.endDay)

        let sparse = try #require(report.limitations.first {
            $0.hasPrefix("Sparse coverage")
        })
        #expect(sparse.contains("3 reading(s)"))
        // 40 readings is above the threshold, so heart rate must not be listed.
        #expect(!sparse.contains("Resting Heart Rate"))
    }

    @Test("deduplication is always disclosed")
    func deduplicationAlwaysDisclosed() async throws {
        let report = try await HealthReport.build(
            store: Self.heartRateStore(), memory: nil, endingOn: Self.endDay)
        // Invisible from the numbers alone: a reader comparing these totals to
        // a raw device export would otherwise find them inexplicably low.
        #expect(report.limitations.contains { $0.contains("counted once rather than") })
        #expect(report.limitations.contains { $0.contains("not medical instruments") })
    }

    // MARK: Annotations

    @Test("annotated periods are listed and stated not to be excluded")
    func annotationsAreListedButNotApplied() async throws {
        let memory = try MemoryStore(inMemory: true)
        try await memory.save(Annotation(
            kind: .ill,
            range: DayRange(start: Self.endDay.adding(days: -6),
                            end: Self.endDay.adding(days: -2)),
            note: "flu"))

        let report = try await HealthReport.build(
            store: Self.heartRateStore(), memory: memory, endingOn: Self.endDay)

        #expect(report.periods.count == 1)
        #expect(report.periods.first?.kind == "Unwell")
        #expect(report.periods.first?.dayCount == 5)

        // The invariant: an annotation explains a dip, it never removes one.
        // Excluding "bad" weeks would make every baseline flattering.
        let note = try #require(report.limitations.first { $0.contains("NOT excluded") })
        #expect(note.contains("1 period(s)"))
    }

    @Test("no memory store means no periods, and no claim about them")
    func noMemoryMeansNoPeriods() async throws {
        let report = try await HealthReport.build(
            store: Self.heartRateStore(), memory: nil, endingOn: Self.endDay)
        #expect(report.periods.isEmpty)
        #expect(!report.limitations.contains { $0.contains("NOT excluded") })
    }

    // MARK: Provenance

    @Test("sources are deduplicated and sorted")
    func sourcesAreDeduplicated() async throws {
        var store = Self.heartRateStore()
        let now = Date()
        store.sampleRows = [
            Sample(metric: "StepCount", value: 100, source: "iPhone",
                   start: now, end: now),
            Sample(metric: "StepCount", value: 200, source: "Apple Watch",
                   start: now, end: now),
            Sample(metric: "StepCount", value: 300, source: "iPhone",
                   start: now, end: now),
        ]

        let report = try await HealthReport.build(
            store: store, memory: nil, endingOn: Self.endDay)

        #expect(report.sources == ["Apple Watch", "iPhone"])
    }

    @Test("the range ends on the requested day and spans the requested months")
    func rangeMatchesRequest() async throws {
        let report = try await HealthReport.build(
            store: Self.heartRateStore(), memory: nil, endingOn: Self.endDay, months: 6)
        #expect(report.range.end == Self.endDay)
        // months x 30, inclusive of both ends.
        #expect(report.range.start == Self.endDay.adding(days: -179))
    }
}
