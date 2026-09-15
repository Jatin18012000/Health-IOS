import Foundation
import Observation
import AURACore
import AURAAnalytics

/// Everything the dashboard shows, in the shape it shows it.
///
/// The view does no arithmetic and no formatting decisions beyond layout. That
/// keeps every figure traceable to `AURAAnalytics`, which is the same guarantee
/// the AI layer relies on — a number on screen and a number she says out loud
/// come from the same place.
@Observable
@MainActor
public final class DashboardViewModel {

    // MARK: State

    public enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case empty(String)
        case failed(String)
    }

    public private(set) var state: LoadState = .idle
    public private(set) var day: CalendarDay
    public private(set) var availableRange: DayRange?

    public private(set) var score: HealthScoreEngine.Score?
    public private(set) var figures: [TrendEngine.Figure] = []
    public private(set) var night: SleepNightSummary?
    public private(set) var weekSteps: [DayValue] = []
    public private(set) var yearlySteps: [YearValue] = []
    public private(set) var hrvWindow: [DayValue] = []
    public private(set) var stepsSourceCount: Int = 1
    public private(set) var stepGoal: Goals.Progress?

    // MARK: Presentation types

    public struct DayValue: Identifiable, Equatable {
        public let id = UUID()
        public let day: CalendarDay
        public let value: Double
    }

    public struct YearValue: Identifiable, Equatable {
        public let id = UUID()
        public let year: Int
        public let mean: Double
    }

    public struct SleepNightSummary: Equatable {
        public let asleepMinutes: Double
        public let coreMinutes: Double
        public let deepMinutes: Double
        public let remMinutes: Double
        public let awakeMinutes: Double
        public let efficiency: Double?
        public let isStaged: Bool
    }

    // MARK: Dependencies

    private let store: any AnalyticsStore
    private let trends: TrendEngine
    private let scores: HealthScoreEngine

    /// User preference, not a statistic. Deliberately not consulted by
    /// `TrendEngine` or `HealthScoreEngine` — a goal must never move a figure
    /// that is supposed to describe reality.
    public var goals: Goals

    public init(store: any AnalyticsStore, goals: Goals = .default,
                day: CalendarDay = CalendarDay(Date())) {
        self.store = store
        self.goals = goals
        self.trends = TrendEngine(store: store)
        self.scores = HealthScoreEngine(store: store)
        self.day = day
    }

    // MARK: Loading

    public func load() async {
        state = .loading
        do {
            guard let range = try await store.availableRange() else {
                state = .empty("No health data yet. Import an Apple Health export to begin.")
                return
            }
            availableRange = range

            // Land on the most recent day that actually has data rather than on
            // today. Opening the app at 06:00 to an empty dashboard, because
            // today has barely started, reads as the app being broken.
            if day > range.end { day = range.end }

            try await reload()
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func show(day newDay: CalendarDay) async {
        guard let range = availableRange,
              newDay >= range.start, newDay <= range.end else { return }
        day = newDay
        do { try await reload() } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func reload() async throws {
        score = try await scores.score(on: day)

        let today = day
        figures = try await withThrowingTaskGroup(of: TrendEngine.Figure?.self) { group in
            for metric in Self.headlineMetrics {
                group.addTask { [trends] in try await trends.figure(metric, on: today) }
            }
            var collected: [TrendEngine.Figure] = []
            for try await figure in group {
                if let figure { collected.append(figure) }
            }
            // The task group finishes out of order; restore the designed order
            // so cards do not rearrange themselves between refreshes.
            return Self.headlineMetrics.compactMap { id in
                collected.first { $0.metric == id }
            }
        }

        let week = DayRange.lastDays(7, endingOn: day)
        let stepRows = try await store.daily(metric: "StepCount", in: week)
        weekSteps = stepRows.compactMap { row in
            row.value.map { DayValue(day: row.day, value: $0) }
        }
        stepsSourceCount = stepRows.first { $0.day == day }?.sourceCount ?? 1
        stepGoal = stepRows.first { $0.day == day }?.value
            .flatMap { goals.progress(for: "StepCount", value: $0) }

        let hrvRange = DayRange.lastDays(7, endingOn: day)
        hrvWindow = try await store.daily(metric: "HeartRateVariabilitySDNN", in: hrvRange)
            .compactMap { row in row.value.map { DayValue(day: row.day, value: $0) } }

        night = try await store.nights(in: DayRange(start: day, end: day)).first.map {
            SleepNightSummary(
                asleepMinutes: $0.asleepMinutes, coreMinutes: $0.coreMinutes,
                deepMinutes: $0.deepMinutes, remMinutes: $0.remMinutes,
                awakeMinutes: $0.awakeMinutes, efficiency: $0.efficiency,
                isStaged: $0.isStaged)
        }

        yearlySteps = try await loadYearlyAverages()
    }

    /// Daily step average per calendar year.
    ///
    /// Worth the extra query: it is the only view in the app that shows the
    /// whole history at once, and a four-year arc is a different kind of fact
    /// from a seven-day one.
    private func loadYearlyAverages() async throws -> [YearValue] {
        guard let range = availableRange else { return [] }
        var out: [YearValue] = []
        for year in range.start.year...range.end.year {
            let span = DayRange(
                start: CalendarDay(year: year, month: 1, day: 1),
                end: CalendarDay(year: year, month: 12, day: 31))
            let values = try await store.daily(metric: "StepCount", in: span)
                .compactMap(\.value)
            if let mean = Stats.mean(values) {
                out.append(YearValue(year: year, mean: mean))
            }
        }
        return out
    }

    static let headlineMetrics = [
        "StepCount", "ActiveEnergyBurned", "DistanceWalkingRunning",
        "AppleExerciseTime", "AppleStandHour", "TimeInDaylight",
        "RestingHeartRate", "HeartRateVariabilitySDNN",
    ]
}
