import Foundation
import GRDB
import AURACore

/// The one implementation of `HealthStore`.
///
/// Raw SQL rather than GRDB's record protocols throughout. The schema is small,
/// fixed, and shared with a Python reference implementation that has to produce
/// identical output — keeping both sides writing the same statements is worth
/// more here than the type safety a record layer would add.
public final class SQLiteHealthStore: HealthStore {

    private let dbQueue: DatabaseQueue
    private let resolver: SourceResolver

    /// Open (creating if needed) the store at `url`.
    public init(url: URL, resolver: SourceResolver = .default) throws {
        var config = Configuration()
        // Health data is read far more than written and the dashboard does many
        // small reads per screen; WAL keeps a slow import from blocking them.
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        self.dbQueue = try DatabaseQueue(path: url.path, configuration: config)
        self.resolver = resolver

        try Schema.migrator().migrate(dbQueue)
        try dbQueue.write { try Schema.seedMetrics($0) }
    }

    /// An in-memory store, for tests.
    public init(inMemory: Bool, resolver: SourceResolver = .default) throws {
        self.dbQueue = try DatabaseQueue()
        self.resolver = resolver
        try Schema.migrator().migrate(dbQueue)
        try dbQueue.write { try Schema.seedMetrics($0) }
    }

    // MARK: - Reads

    public func daily(metric: String, in range: DayRange) async throws -> [DailyMetric] {
        try await dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT day, identifier, domain, unit, value, value_min, value_max,
                       sample_count, source_count
                FROM daily_metrics
                WHERE identifier = ? AND day BETWEEN ? AND ?
                ORDER BY day
                """, arguments: [metric, range.start.description, range.end.description])
                .compactMap(Self.dailyMetric(from:))
        }
    }

    public func daily(domain: MetricDomain, on day: CalendarDay) async throws -> [DailyMetric] {
        try await dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT day, identifier, domain, unit, value, value_min, value_max,
                       sample_count, source_count
                FROM daily_metrics
                WHERE domain = ? AND day = ?
                ORDER BY identifier
                """, arguments: [domain.rawValue, day.description])
                .compactMap(Self.dailyMetric(from:))
        }
    }

    public func nights(in range: DayRange) async throws -> [SleepNight] {
        try await dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT night_of, in_bed_start, in_bed_end, in_bed_min, asleep_min,
                       core_min, deep_min, rem_min, awake_min, efficiency, staged, sources
                FROM sleep_nights
                WHERE night_of BETWEEN ? AND ?
                ORDER BY night_of
                """, arguments: [range.start.description, range.end.description])
                .compactMap(Self.sleepNight(from:))
        }
    }

    public func availableRange() async throws -> DayRange? {
        try await dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql:
                    "SELECT MIN(day), MAX(day) FROM daily_metrics"),
                  let lo: String = row[0], let hi: String = row[1],
                  let start = CalendarDay(lo), let end = CalendarDay(hi)
            else { return nil }
            return DayRange(start: start, end: end)
        }
    }

    public func samples(metric: String, in range: DayRange) async throws -> [Sample] {
        let (from, to) = Self.bounds(of: range)
        return try await dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT m.identifier, s.value, s.category, so.name, d.descriptor,
                       s.start_at, s.end_at
                FROM samples s
                JOIN metrics m  ON m.id  = s.metric_id
                JOIN sources so ON so.id = s.source_id
                LEFT JOIN devices d ON d.id = s.device_id
                WHERE m.identifier = ? AND s.start_at >= ? AND s.start_at < ?
                ORDER BY s.start_at
                """, arguments: [metric, from, to])
                .map { row in
                    Sample(metric: row[0], value: row[1], category: row[2],
                           source: row[3], device: row[4],
                           start: Date(timeIntervalSince1970: row[5]),
                           end: Date(timeIntervalSince1970: row[6]))
                }
        }
    }

    // MARK: - Writes

    public func ingest(_ batch: [Sample]) async throws -> IngestResult {
        try await dbQueue.write { db in try self.ingest(batch, into: db) }
    }

    /// Synchronous ingest, for the import path.
    ///
    /// Exists because the importer is a synchronous SAX parse and the whole
    /// point of its batching is that memory stays flat. Bridging each batch
    /// into an async write means either collecting them all first — which
    /// defeats the batching entirely — or blocking a thread on a semaphore.
    /// A synchronous write is the honest version: the parse and the store run
    /// on the same background thread, and the store provides natural
    /// backpressure by simply taking as long as it takes.
    public func ingestSynchronously(_ batch: [Sample]) throws -> IngestResult {
        try dbQueue.write { db in try self.ingest(batch, into: db) }
    }

    private func ingest(_ batch: [Sample], into db: Database) throws -> IngestResult {
        guard !batch.isEmpty else {
            return IngestResult(seen: 0, inserted: 0, duplicates: 0,
                                rejected: [:], affected: nil)
        }

        // Filter identical records within the batch before touching the
        // database. The reference export contains 118 of them, and without this
        // the stored sample count and the rollups' sample_count disagree the
        // moment an export repeats a record.
        var seenInBatch = Set<BatchKey>()
        var unique: [Sample] = []
        unique.reserveCapacity(batch.count)
        for sample in batch {
            let key = BatchKey(sample)
            if seenInBatch.insert(key).inserted { unique.append(sample) }
        }
        let withinBatchDuplicates = batch.count - unique.count

        var rejected: [String: Int] = [:]
        var inserted = 0

        do {
            let metricIDs = try Self.idMap(db, table: "metrics", column: "identifier")

            for sample in unique {
                guard let metricID = metricIDs[sample.metric] else {
                    rejected["unmapped:\(sample.metric)", default: 0] += 1
                    continue
                }
                let sourceID = try self.sourceID(db, name: sample.source)
                let deviceID = try sample.device.map { try self.deviceID(db, descriptor: $0) }

                // Idempotency, without a permanent index. The NOT EXISTS guard
                // probes idx_samples_metric_start — (metric_id, start_at)
                // narrows to a handful of rows before the rest is compared.
                //
                // `IS` rather than `=` on value and category: both are nullable,
                // and `=` never matches NULL. With `=`, every category sample
                // (all sleep, all stand hours) would re-insert on every import.
                try db.execute(sql: """
                    INSERT INTO samples (metric_id, source_id, device_id, value, category, start_at, end_at)
                    SELECT :metric, :source, :device, :value, :category, :start, :end
                    WHERE NOT EXISTS (
                        SELECT 1 FROM samples
                        WHERE metric_id = :metric AND start_at = :start AND end_at = :end
                          AND source_id = :source AND value IS :value AND category IS :category
                    )
                    """, arguments: [
                        "metric": metricID, "source": sourceID, "device": deviceID,
                        "value": sample.value, "category": sample.category,
                        "start": Int(sample.start.timeIntervalSince1970),
                        "end": Int(sample.end.timeIntervalSince1970),
                    ])
                inserted += db.changesCount
            }

            for (detail, count) in rejected {
                try db.execute(sql: """
                    INSERT INTO ingest_issues (kind, detail, count, seen_at) VALUES (?, ?, ?, ?)
                    """, arguments: [detail.split(separator: ":").first.map(String.init) ?? "unknown",
                                     detail, count, Int(Date().timeIntervalSince1970)])
            }
        }

        let days = unique.map { CalendarDay($0.start) }
        let affected = days.min().flatMap { lo in days.max().map { DayRange(start: lo, end: $0) } }

        // Everything that was neither stored nor rejected was already known:
        // identical records inside this batch, plus records a previous import
        // of an overlapping export already wrote.
        let rejectedCount = rejected.values.reduce(0, +)
        _ = withinBatchDuplicates  // folded into the figure below

        return IngestResult(
            seen: batch.count,
            inserted: inserted,
            duplicates: batch.count - inserted - rejectedCount,
            rejected: rejected,
            affected: affected)
    }

    public func rebuildRollups(for range: DayRange) async throws {
        try await dbQueue.write { db in
            try RollupBuilder(resolver: self.resolver).rebuild(db, range: range)
        }
    }

    // MARK: - Helpers

    private struct BatchKey: Hashable {
        let metric: String, source: String, category: String?
        let value: Double?, start: Date, end: Date
        init(_ s: Sample) {
            metric = s.metric; source = s.source; category = s.category
            value = s.value; start = s.start; end = s.end
        }
    }

    private func sourceID(_ db: Database, name: String) throws -> Int64 {
        if let id = try Int64.fetchOne(db, sql: "SELECT id FROM sources WHERE name = ?",
                                       arguments: [name]) {
            return id
        }
        try db.execute(sql: "INSERT INTO sources (name, priority) VALUES (?, ?)",
                       arguments: [name, resolver.rank(of: name)])
        return db.lastInsertedRowID
    }

    private func deviceID(_ db: Database, descriptor: String) throws -> Int64 {
        if let id = try Int64.fetchOne(db, sql: "SELECT id FROM devices WHERE descriptor = ?",
                                       arguments: [descriptor]) {
            return id
        }
        try db.execute(sql: "INSERT INTO devices (descriptor) VALUES (?)",
                       arguments: [descriptor])
        return db.lastInsertedRowID
    }

    private static func idMap(_ db: Database, table: String, column: String) throws -> [String: Int64] {
        var map: [String: Int64] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT \(column), id FROM \(table)") {
            map[row[0]] = row[1]
        }
        return map
    }

    /// Unix-second bounds for a day range, in the local calendar.
    ///
    /// Local, deliberately: a day's step count is bounded by when you woke up
    /// and went to bed where you were, not by a UTC boundary.
    static func bounds(of range: DayRange) -> (Int, Int) {
        let cal = Calendar.current
        let from = range.start.date(in: cal)
        let to = cal.date(byAdding: .day, value: 1, to: range.end.date(in: cal)) ?? range.end.date(in: cal)
        return (Int(from.timeIntervalSince1970), Int(to.timeIntervalSince1970))
    }

    private static func dailyMetric(from row: Row) -> DailyMetric? {
        guard let day = CalendarDay(row[0] as String),
              let domain = MetricDomain(rawValue: row[2] as String)
        else { return nil }
        return DailyMetric(
            day: day, metric: row[1], domain: domain,
            unit: Unit(rawValue: row[3]), value: row[4],
            min: row[5], max: row[6],
            sampleCount: row[7], sourceCount: row[8])
    }

    private static func sleepNight(from row: Row) -> SleepNight? {
        guard let night = CalendarDay(row[0] as String) else { return nil }
        return SleepNight(
            nightOf: night,
            inBedStart: Date(timeIntervalSince1970: row[1] ?? 0),
            inBedEnd: Date(timeIntervalSince1970: row[2] ?? 0),
            inBedMinutes: row[3] ?? 0, asleepMinutes: row[4] ?? 0,
            coreMinutes: row[5] ?? 0, deepMinutes: row[6] ?? 0,
            remMinutes: row[7] ?? 0, awakeMinutes: row[8] ?? 0,
            efficiency: row[9],
            isStaged: (row[10] as Int) == 1,
            sources: (row[11] as String? ?? "").split(separator: ",").map(String.init))
    }
}
