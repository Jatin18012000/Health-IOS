import Foundation

/// How a metric's samples collapse into a single daily figure.
public enum Aggregation: String, Sendable, Codable {
    /// Add the samples together. Requires source deduplication first.
    case sum
    /// Arithmetic mean of the samples.
    case mean
    /// Mean, plus the day's min and max retained (heart rate, for instance).
    case minMax
    /// The most recent sample wins (body mass, height).
    case last
    /// Number of qualifying samples (stand hours, exposure events).
    case count
    /// Samples are time intervals to be unioned, not numbers (sleep).
    case interval
}

public enum MetricDomain: String, Sendable, Codable, CaseIterable {
    case activity, heart, sleep, mobility, environment, body, mind
}

/// A canonical unit. Conversion happens once, at ingest -- never at display
/// time, so nothing downstream has to guess what a number means.
public struct Unit: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let count       = Unit(rawValue: "count")
    public static let kilometres  = Unit(rawValue: "km")
    public static let metres      = Unit(rawValue: "m")
    public static let centimetres = Unit(rawValue: "cm")
    public static let kilograms   = Unit(rawValue: "kg")
    public static let kilocalories = Unit(rawValue: "kcal")
    public static let minutes     = Unit(rawValue: "min")
    public static let milliseconds = Unit(rawValue: "ms")
    public static let beatsPerMinute   = Unit(rawValue: "bpm")
    public static let breathsPerMinute = Unit(rawValue: "breaths/min")
    public static let percent     = Unit(rawValue: "%")
    public static let celsius     = Unit(rawValue: "degC")
    public static let mmHg        = Unit(rawValue: "mmHg")
    public static let decibelsASPL = Unit(rawValue: "dBASPL")
    public static let kmPerHour   = Unit(rawValue: "km/hr")
    public static let metresPerSecond = Unit(rawValue: "m/s")
    public static let vo2         = Unit(rawValue: "mL/min-kg")
    public static let met         = Unit(rawValue: "kcal/hr-kg")

    /// Raw unit spellings Apple emits that mean this same canonical unit.
    ///
    /// Scoped per canonical unit on purpose. A single global alias table gets
    /// this wrong: `count/min` means beats per minute for heart rate and
    /// breaths per minute for respiratory rate. And `Cal` in a HealthKit
    /// export is a *kilo*calorie -- reading it as a calorie is a silent
    /// 1000x error that no test will catch unless you look for it.
    public var acceptedSpellings: Set<String> {
        switch self {
        case .kilocalories:     return ["kcal", "Cal"]
        case .beatsPerMinute:   return ["bpm", "count/min"]
        case .breathsPerMinute: return ["breaths/min", "count/min"]
        case .met:              return ["kcal/hr-kg", "kcal/hr\u{00b7}kg"]
        case .vo2:              return ["mL/min-kg", "mL/min\u{00b7}kg"]
        default:                return [rawValue]
        }
    }

    public func accepts(_ raw: String) -> Bool {
        raw.isEmpty || raw == "None" || acceptedSpellings.contains(raw)
    }
}

/// One tracked health metric: what it is, what unit it lives in, and how it
/// collapses to a day.
public struct Metric: Hashable, Sendable, Codable, Identifiable {
    /// The HealthKit identifier with the `HKQuantityTypeIdentifier` /
    /// `HKCategoryTypeIdentifier` prefix stripped, e.g. `StepCount`.
    public let id: String
    public let domain: MetricDomain
    public let unit: Unit
    public let aggregation: Aggregation

    /// True when the samples represent an accumulating quantity over a time
    /// interval (steps, distance, energy). These and only these need source
    /// deduplication before summing -- see `SourceResolver`.
    public let isCumulative: Bool

    /// Human label for the dashboard.
    public let title: String

    public init(id: String, domain: MetricDomain, unit: Unit,
                aggregation: Aggregation, isCumulative: Bool, title: String) {
        self.id = id
        self.domain = domain
        self.unit = unit
        self.aggregation = aggregation
        self.isCumulative = isCumulative
        self.title = title
    }
}

/// A single normalized reading.
public struct Sample: Hashable, Sendable {
    public let metric: String
    public let value: Double?
    /// Set instead of `value` for category samples (sleep stages, stand hours).
    public let category: String?
    public let source: String
    public let device: String?
    public let start: Date
    public let end: Date

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    public init(metric: String, value: Double?, category: String? = nil,
                source: String, device: String? = nil, start: Date, end: Date) {
        self.metric = metric
        self.value = value
        self.category = category
        self.source = source
        self.device = device
        self.start = start
        self.end = end
    }
}

/// One metric's value for one day -- the row the dashboard actually reads.
public struct DailyMetric: Hashable, Sendable, Codable {
    public let day: CalendarDay
    public let metric: String
    public let domain: MetricDomain
    public let unit: Unit
    public let value: Double?
    public let min: Double?
    public let max: Double?
    public let sampleCount: Int
    /// How many distinct devices contributed. Greater than one means the value
    /// went through deduplication and is not a naive sum.
    public let sourceCount: Int

    public init(day: CalendarDay, metric: String, domain: MetricDomain, unit: Unit,
                value: Double?, min: Double? = nil, max: Double? = nil,
                sampleCount: Int, sourceCount: Int) {
        self.day = day
        self.metric = metric
        self.domain = domain
        self.unit = unit
        self.value = value
        self.min = min
        self.max = max
        self.sampleCount = sampleCount
        self.sourceCount = sourceCount
    }
}
