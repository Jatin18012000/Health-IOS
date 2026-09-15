import Foundation
import AURACore
import AURAStore

/// The read-only surface the analytics layer needs.
///
/// A narrower protocol than `HealthStore` on purpose: nothing above this line
/// has any business writing health data, and the type system is a cheaper way
/// to guarantee that than a code review is.
public protocol AnalyticsStore: Sendable {
    func daily(metric: String, in range: DayRange) async throws -> [DailyMetric]
    func daily(domain: MetricDomain, on day: CalendarDay) async throws -> [DailyMetric]
    func nights(in range: DayRange) async throws -> [SleepNight]
    func samples(metric: String, in range: DayRange) async throws -> [Sample]
}

/// Every `HealthStore` is a valid `AnalyticsStore`.
extension SQLiteHealthStore: AnalyticsStore {}
