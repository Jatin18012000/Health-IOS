import Foundation

/// A calendar date with no time and no zone drift.
///
/// Health data is lived in local time -- a day's step count is bounded by when
/// you woke up and went to bed where you were, not by a UTC boundary. Storing
/// days as `Date` invites an off-by-one every time a value crosses midnight in
/// a different zone, so days are their own type.
public struct CalendarDay: Hashable, Comparable, Sendable, Codable,
                           CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year; self.month = month; self.day = day
    }

    public init(_ date: Date, in calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    /// `2026-09-15` -- sorts lexicographically, which is why it is the storage form.
    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public init?(_ string: String) {
        let parts = string.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public func date(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    public func adding(days: Int, in calendar: Calendar = .current) -> CalendarDay {
        CalendarDay(calendar.date(byAdding: .day, value: days, to: date(in: calendar))!,
                    in: calendar)
    }

    public static func < (a: CalendarDay, b: CalendarDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}

/// An inclusive span of days. The unit the dashboard and the AI both reason in.
public struct DayRange: Hashable, Sendable, Codable {
    public let start: CalendarDay
    public let end: CalendarDay

    public init(start: CalendarDay, end: CalendarDay) {
        self.start = start; self.end = end
    }

    public static func lastDays(_ n: Int, endingOn end: CalendarDay) -> DayRange {
        DayRange(start: end.adding(days: -(n - 1)), end: end)
    }
}
