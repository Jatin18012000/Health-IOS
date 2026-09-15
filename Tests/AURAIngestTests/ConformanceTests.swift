import Testing
import Foundation
@testable import AURAIngest
@testable import AURAStore
@testable import AURACore

/// The acceptance test for M1 and M2.
///
/// Reads the SAME `expected.json` that `tools/conformance.py` asserts against,
/// so the Swift store and the Python reference cannot drift apart without a
/// test going red on one side or the other. There is one source of truth for
/// what correct ingestion means, and it is that file.
///
/// The fixture is deliberately small and deliberately nasty — 32 records
/// covering multi-source overlap, `Cal` versus `kcal`, `count/min` meaning two
/// different things, both sleep eras, an entity-encoded source name, a
/// US-locale unit, an unknown metric, an instantaneous cumulative sample, a
/// missing `endDate`, and a byte-identical duplicate.
@Suite("Ingestion conformance")
struct ConformanceTests {

    // MARK: Fixture loading

    struct Expected: Decodable {
        struct Totals: Decodable {
            let samples_stored: Int
            let daily_metric_rows: Int
            let nights: Int
        }
        struct Daily: Decodable {
            let day: String
            let metric: String
            let unit: String
            let value: Double
            let samples: Int
            let sources: Int
            let method: String
            let min: Double?
            let max: Double?
            let _why: String?
        }
        struct Night: Decodable {
            let night_of: String
            let in_bed_min: Double
            let asleep_min: Double
            let core_min: Double
            let deep_min: Double
            let rem_min: Double
            let awake_min: Double
            let efficiency: Double
            let staged: Int
            let _why: String?
        }
        struct Absent: Decodable { let day: String; let metric: String; let _why: String }

        let totals: Totals
        let source_ranks: [String: RankOrNote]
        let daily_metrics: [Daily]
        let absent_metrics: [Absent]
        let sleep_nights: [Night]
    }

    /// `source_ranks` mixes integer ranks with a `_why` string.
    enum RankOrNote: Decodable {
        case rank(Int), note(String)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let i = try? c.decode(Int.self) { self = .rank(i) }
            else { self = .note(try c.decode(String.self)) }
        }
        var value: Int? { if case .rank(let i) = self { return i }; return nil }
    }

    static var fixtureDirectory: URL {
        // Tests/AURAIngestTests/ConformanceTests.swift -> Tests/Fixtures/edge-cases
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AURAIngestTests
            .deletingLastPathComponent()   // Tests
            .appending(path: "Fixtures/edge-cases")
    }

    static func loadExpected() throws -> Expected {
        let data = try Data(contentsOf: fixtureDirectory.appending(path: "expected.json"))
        return try JSONDecoder().decode(Expected.self, from: data)
    }

    /// Import the fixture into a fresh in-memory store and rebuild its rollups.
    static func importedStore() async throws -> SQLiteHealthStore {
        let store = try SQLiteHealthStore(inMemory: true)
        let session = ImportSession(store: store)
        let outcome = try await session.run(from: fixtureDirectory)
        #expect(outcome.recordsParsed > 0, "the fixture produced no samples at all")
        return store
    }

    // MARK: Tests

    @Test("totals match the reference pipeline")
    func totals() async throws {
        let expected = try Self.loadExpected()
        let store = try await Self.importedStore()

        let range = try await store.availableRange()
        #expect(range != nil)

        var dailyRows = 0
        for metric in MetricCatalog.all {
            dailyRows += try await store.daily(metric: metric.id, in: range!).count
        }
        #expect(dailyRows == expected.totals.daily_metric_rows)
        #expect(try await store.nights(in: range!).count == expected.totals.nights)
    }

    @Test("source trust order survives entity decoding")
    func sourceRanks() throws {
        let expected = try Self.loadExpected()
        let resolver = SourceResolver.default

        for (name, entry) in expected.source_ranks {
            guard let rank = entry.value else { continue }
            // The Watch's name carries a NON-BREAKING SPACE, written in the
            // fixture as &#160;. Undecoded it ranks 99, which silently inverts
            // every deduplicated total below. XMLParser decodes it; a
            // hand-rolled scanner does not.
            #expect(resolver.rank(of: name) == rank,
                    "\(name) ranked \(resolver.rank(of: name)), expected \(rank)")
        }
    }

    @Test("every daily metric matches its hand-computed value")
    func dailyMetrics() async throws {
        let expected = try Self.loadExpected()
        let store = try await Self.importedStore()

        for e in expected.daily_metrics {
            guard let day = CalendarDay(e.day) else {
                Issue.record("bad fixture day \(e.day)"); continue
            }
            let rows = try await store.daily(metric: e.metric, in: DayRange(start: day, end: day))
            guard let row = rows.first else {
                Issue.record("no row for \(e.day) \(e.metric) — \(e._why ?? "")")
                continue
            }
            #expect(abs((row.value ?? 0) - e.value) < 0.01,
                    "\(e.day) \(e.metric): got \(row.value ?? -1), expected \(e.value). \(e._why ?? "")")
            #expect(row.unit.rawValue == e.unit)
            #expect(row.sampleCount == e.samples)
            #expect(row.sourceCount == e.sources)
            if let lo = e.min { #expect(abs((row.min ?? 0) - lo) < 0.01) }
            if let hi = e.max { #expect(abs((row.max ?? 0) - hi) < 0.01) }
        }
    }

    @Test("records with unusable units are rejected, not converted")
    func rejections() async throws {
        let expected = try Self.loadExpected()
        let store = try await Self.importedStore()

        for e in expected.absent_metrics {
            guard let day = CalendarDay(e.day) else { continue }
            let rows = try await store.daily(metric: e.metric, in: DayRange(start: day, end: day))
            #expect(rows.isEmpty, "\(e.metric) should have been rejected. \(e._why)")
        }
    }

    @Test("sleep unions intervals and keeps the two eras apart")
    func sleep() async throws {
        let expected = try Self.loadExpected()
        let store = try await Self.importedStore()

        for e in expected.sleep_nights {
            guard let night = CalendarDay(e.night_of) else { continue }
            let rows = try await store.nights(in: DayRange(start: night, end: night))
            guard let n = rows.first else {
                Issue.record("no night for \(e.night_of) — \(e._why ?? "")"); continue
            }
            // The union, never the sum: the InBed interval contains every stage
            // inside it, so adding durations counts the same minutes repeatedly.
            #expect(abs(n.inBedMinutes - e.in_bed_min) < 0.1, e._why ?? "")
            #expect(abs(n.asleepMinutes - e.asleep_min) < 0.1)
            #expect(abs(n.coreMinutes - e.core_min) < 0.1)
            #expect(abs(n.deepMinutes - e.deep_min) < 0.1)
            #expect(abs(n.remMinutes - e.rem_min) < 0.1)
            #expect(abs(n.awakeMinutes - e.awake_min) < 0.1)
            #expect(abs((n.efficiency ?? 0) - e.efficiency) < 0.1)
            #expect(n.isStaged == (e.staged == 1))
        }
    }

    @Test("re-importing the same export changes nothing")
    func idempotency() async throws {
        let expected = try Self.loadExpected()
        let store = try SQLiteHealthStore(inMemory: true)
        let session = ImportSession(store: store)

        _ = try await session.run(from: Self.fixtureDirectory)
        let second = try await session.run(from: Self.fixtureDirectory)

        // Every Apple Health export contains ALL history, so the second import
        // is almost entirely records already stored. That is the normal case.
        #expect(second.samplesStored == 0,
                "re-import stored \(second.samplesStored) rows; it must store none")
        #expect(second.duplicates > 0)

        guard let day = CalendarDay("2025-03-10") else { return }
        let steps = try await store.daily(metric: "StepCount",
                                          in: DayRange(start: day, end: day))
        let expectedSteps = expected.daily_metrics
            .first { $0.day == "2025-03-10" && $0.metric == "StepCount" }?.value ?? 0
        #expect(abs((steps.first?.value ?? 0) - expectedSteps) < 0.01,
                "a re-import doubled the day")
    }
}
