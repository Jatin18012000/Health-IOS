import Foundation
import AURACore
import AURAAnalytics

/// The one time she speaks first.
///
/// `docs/INTELLIGENCE.md`: *keep these rare and genuinely informative; a
/// companion who interrupts constantly gets muted.* That is not a style note —
/// it is the entire design constraint, and it is why this type spends most of
/// its code deciding **not** to say anything.
public struct MorningBrief: Sendable {

    public struct Outcome: Sendable {
        public let text: String
        /// What made it worth interrupting for. Empty means it was not.
        public let reasons: [String]
        public var isWorthSending: Bool { !reasons.isEmpty && !text.isEmpty }
    }

    let trends: TrendEngine
    let scores: HealthScoreEngine
    let briefBuilder: BriefBuilder
    let model: any LanguageModel

    public init(store: any AnalyticsStore, briefBuilder: BriefBuilder,
                model: any LanguageModel) {
        self.trends = TrendEngine(store: store)
        self.scores = HealthScoreEngine(store: store)
        self.briefBuilder = briefBuilder
        self.model = model
    }

    /// Generate the brief, or decide there is nothing worth saying.
    public func compose(for day: CalendarDay) async throws -> Outcome {
        let brief = try await briefBuilder.brief(for: day)
        let reasons = try await noteworthy(on: day, brief: brief)

        // The silent path is the common one and the important one. "Everything
        // is normal" is not news, and a notification that says it every morning
        // trains you to dismiss the ones that matter.
        guard !reasons.isEmpty else {
            return Outcome(text: "", reasons: [])
        }

        let text = try await model.complete(
            system: Self.system,
            user: Conversation.userPrompt(
                question: "Give them their morning brief. Lead with: "
                        + reasons.joined(separator: "; "),
                brief: brief),
            onToken: { _ in })

        return Outcome(text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                       reasons: reasons)
    }

    /// The bar for interrupting someone's morning.
    ///
    /// Deliberately high and deliberately explicit — a threshold you can read
    /// is a threshold you can argue with, where "the model thought it was
    /// interesting" is not.
    func noteworthy(on day: CalendarDay, brief: HealthBrief) async throws -> [String] {
        var reasons: [String] = []

        // A genuine outlier against their own history.
        for figure in brief.figures {
            guard let percentile = figure.personalPercentile else { continue }
            if percentile <= 0.05 {
                reasons.append("\(figure.label) is near the bottom of their year")
            } else if percentile >= 0.95 {
                reasons.append("\(figure.label) is near the top of their year")
            }
        }

        // Last night specifically — it is the thing a morning brief is for.
        if let night = try? await sleepWasUnusual(on: day) {
            reasons.append(night)
        }

        // A goal met, but only when it is not routine. Congratulating someone
        // daily for a thing they do daily is noise.
        for goal in brief.goals where goal.isMet {
            let trend = try await trends.trend(metric: goal.metric, endingOn: day, days: 7)
            if let current = trend.current, current < goal.target {
                reasons.append("they met their \(goal.label) goal on a week they mostly have not")
            }
        }

        // An observation she is actually confident about.
        for observation in brief.observations where observation.confidence >= 0.6 {
            reasons.append(observation.text)
        }

        return Array(reasons.prefix(3))
    }

    private func sleepWasUnusual(on day: CalendarDay) async throws -> String? {
        guard let figure = try await trends.figure("HeartRateVariabilitySDNN", on: day),
              let percentile = figure.personalPercentile, percentile <= 0.1
        else { return nil }
        return "their recovery is unusually low this morning"
    }

    static let system = """
        You are AURA. It is early morning and you are speaking first, which you \
        rarely do — so this has to be worth their attention.

        Two sentences. Lead with the thing that made it worth saying. No \
        greeting beyond their name, no summary of everything, no advice unless \
        they asked for some yesterday.

        Every rule about numbers still applies: only what is in the DATA block.
        """
}

/// Fires the morning brief once a day.
///
/// A timer rather than a background task: the app is open or it is not, and a
/// health companion that runs invisibly in the background to watch you is a
/// different and less welcome product.
@MainActor
public final class MorningBriefScheduler {

    public private(set) var lastSent: CalendarDay?
    public var hour = 8

    private var timer: Timer?
    private let onBrief: @MainActor (MorningBrief.Outcome) -> Void

    public init(onBrief: @escaping @MainActor (MorningBrief.Outcome) -> Void) {
        self.onBrief = onBrief
    }

    public func start(check: @escaping @Sendable () async -> MorningBrief.Outcome?) {
        stop()
        // Every fifteen minutes, not every second. The window is an hour wide
        // and precision buys nothing.
        timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.tick(check) }
        }
        Task { await tick(check) }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick(_ check: @escaping @Sendable () async -> MorningBrief.Outcome?) async {
        let now = Date()
        let today = CalendarDay(now)
        guard lastSent != today,
              Calendar.current.component(.hour, from: now) >= hour,
              // Past mid-morning it is not a morning brief any more. Opening
              // the app at 4pm should not produce one.
              Calendar.current.component(.hour, from: now) < hour + 3
        else { return }

        guard let outcome = await check(), outcome.isWorthSending else {
            // Mark the day done either way. Having decided there was nothing to
            // say, she must not reconsider at 08:15 and again at 08:30.
            lastSent = today
            return
        }

        lastSent = today
        onBrief(outcome)
    }
}
