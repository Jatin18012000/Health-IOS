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

/// One night, reconstructed from overlapping `SleepAnalysis` intervals.
public struct SleepNight: Hashable, Sendable, Codable {
    public let nightOf: CalendarDay
    public let inBedStart: Date
    public let inBedEnd: Date
    public let inBedMinutes: Double
    public let asleepMinutes: Double
    public let coreMinutes: Double
    public let deepMinutes: Double
    public let remMinutes: Double
    public let awakeMinutes: Double
    public let efficiency: Double?

    /// Whether this night has real sleep stages.
    ///
    /// Not cosmetic. In the reference export only 53 of 819 nights are staged
    /// -- the rest predate the Watch and carry in-bed intervals only, where
    /// "asleep" means "the phone thought you were in bed". Charting the two
    /// eras on one axis without saying which is which invents a trend that is
    /// really just a hardware upgrade.
    public let isStaged: Bool
    public let sources: [String]

    public init(nightOf: CalendarDay, inBedStart: Date, inBedEnd: Date,
                inBedMinutes: Double, asleepMinutes: Double, coreMinutes: Double,
                deepMinutes: Double, remMinutes: Double, awakeMinutes: Double,
                efficiency: Double?, isStaged: Bool, sources: [String]) {
        self.nightOf = nightOf
        self.inBedStart = inBedStart
        self.inBedEnd = inBedEnd
        self.inBedMinutes = inBedMinutes
        self.asleepMinutes = asleepMinutes
        self.coreMinutes = coreMinutes
        self.deepMinutes = deepMinutes
        self.remMinutes = remMinutes
        self.awakeMinutes = awakeMinutes
        self.efficiency = efficiency
        self.isStaged = isStaged
        self.sources = sources
    }
}
