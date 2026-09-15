import Foundation

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
