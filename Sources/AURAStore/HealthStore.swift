import Foundation
import AURACore

/// Everything the app can ask of stored health data.
///
/// One protocol, one implementation (`SQLiteHealthStore`), because a single-user
/// local app has no business carrying an abstraction it will never swap. It is
/// a protocol only so tests can use an in-memory double without a file.
public protocol HealthStore: Sendable {
    // Reads -- the dashboard path. All of these must stay well under a frame
    // budget; on the reference dataset the slowest is ~7 ms across 1,450 days.
    func daily(metric: String, in range: DayRange) async throws -> [DailyMetric]
    func daily(domain: MetricDomain, on day: CalendarDay) async throws -> [DailyMetric]
    func nights(in range: DayRange) async throws -> [SleepNight]
    func availableRange() async throws -> DayRange?

    /// Raw samples, for drill-down only. Never used to build a dashboard card
    /// -- that is what `daily` is for.
    func samples(metric: String, in range: DayRange) async throws -> [Sample]

    // Writes -- the import path.
    func ingest(_ batch: [Sample]) async throws -> IngestResult
    func rebuildRollups(for range: DayRange) async throws
}

public struct IngestResult: Sendable {
    public let seen: Int
    public let inserted: Int
    /// Re-importing an overlapping export is the normal case, not an error:
    /// every export contains all history, so the second import is ~99%
    /// duplicates and must be idempotent.
    public let duplicates: Int
    public let rejected: [String: Int]
    public let affected: DayRange?

    public init(seen: Int, inserted: Int, duplicates: Int,
                rejected: [String: Int], affected: DayRange?) {
        self.seen = seen
        self.inserted = inserted
        self.duplicates = duplicates
        self.rejected = rejected
        self.affected = affected
    }
}
