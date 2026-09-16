import SwiftUI
import AURACore
import AURAAnalytics
import AURADesign
import AURACharacter

/// The overview screen.
///
/// Three columns: today's figures, the companion, the charts. Matches the
/// published design, and like it, shows nothing it cannot source.
public struct DashboardView: View {
    @Environment(\.theme) private var theme
    @State private var model: DashboardViewModel

    /// Set when the shell has somewhere to send an empty dashboard. An empty
    /// state that names the fix and can't perform it is a dead end.
    private let onImport: (() -> Void)?

    public init(model: DashboardViewModel, onImport: (() -> Void)? = nil) {
        _model = State(wrappedValue: model)
        self.onImport = onImport
    }

    public var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            AmbientField()

            switch model.state {
            case .idle, .loading:
                ProgressView().controlSize(.large).tint(theme.primary)

            case .empty(let message), .failed(let message):
                // An honest empty state rather than a dashboard of zeroes.
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 30))
                        .foregroundStyle(theme.textSecondary)
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)

                    if case .empty = model.state, let onImport {
                        Button("Import an export…", action: onImport)
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.primary)
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .background(Capsule().fill(theme.primary.opacity(0.14)))
                            .padding(.top, 4)
                    }
                }

            case .ready:
                content
            }
        }
        .task { await model.load() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            HStack(alignment: .top, spacing: 16) {
                leftColumn.frame(width: 306)
                centreColumn.frame(maxWidth: .infinity)
                rightColumn.frame(width: 320)
            }
        }
        .padding(22)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(greeting)
                    .font(.system(size: 25, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                if let line = summaryLine {
                    Text(line)
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: 620, alignment: .leading)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(model.day.date().formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                Text(model.day.date().formatted(.dateTime.day().month(.wide).year()))
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12:  "Good morning"
        case 12..<18: "Good afternoon"
        default:      "Good evening"
        }
    }

    /// One sentence of real context, assembled from computed figures only.
    ///
    /// Deliberately not model-generated: this line is on screen before the LLM
    /// has loaded, and a greeting that appears three seconds late reads as a
    /// stutter. She elaborates on it in conversation; this states it.
    private var summaryLine: String? {
        guard let score = model.score else { return nil }
        if score.isPartial {
            return "Today is still in progress — \(Int(score.completeness * 100))% of it recorded so far."
        }
        guard let hrv = model.figures.first(where: { $0.metric == "HeartRateVariabilitySDNN" }),
              let percentile = hrv.personalPercentile, let night = model.night
        else { return nil }

        let hours = Int(night.asleepMinutes) / 60
        let minutes = Int(night.asleepMinutes) % 60
        let sleepPart = "You slept \(hours)h \(minutes)m"
            + (night.efficiency.map { " at \(Int($0))% efficiency" } ?? "")

        if percentile < 0.15 {
            return sleepPart + ", but your HRV is in the bottom "
                + "\(Int(percentile * 100))% of your \(hrv.baselineCount) readings. "
                + "Recovery is low."
        }
        return sleepPart + "."
    }

    // MARK: Columns

    private var leftColumn: some View {
        VStack(spacing: 14) {
            GlassPanel {
                VStack(alignment: .leading, spacing: 14) {
                    PanelLabel("Today")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                              alignment: .leading, spacing: 15) {
                        ForEach(model.figures.prefix(6), id: \.metric) { figure in
                            VStack(alignment: .leading, spacing: 2) {
                                MetricValue(Self.format(figure), unit: figure.unit.rawValue)
                                Text(figure.title)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(theme.textSecondary)
                            }
                        }
                    }
                }
            }

            GlassPanel {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        PanelLabel("Steps · 7 days")
                        Spacer()
                        if let goal = model.stepGoal {
                            // Naming the target alongside the percentage: "127%"
                            // alone is meaningless without knowing of what.
                            Text("\(Int(goal.percent))% of \(goal.target.formatted(.number.precision(.fractionLength(0))))")
                                .font(.system(size: 10))
                                .foregroundStyle(goal.isMet ? theme.dataSeries[3] : theme.textSecondary)
                        }
                    }
                    if model.weekSteps.isEmpty {
                        EmptyMetricState("No step data in this window.")
                    } else {
                        BarRow(bars: model.weekSteps.map { point in
                            BarRow.Bar(
                                label: point.day.date().formatted(.dateTime.weekday(.narrow)),
                                value: point.value,
                                isHighlighted: point.day == model.day)
                        })
                        ProvenanceBadge(sourceCount: model.stepsSourceCount)
                    }
                }
            }

            GlassPanel {
                VStack(alignment: .leading, spacing: 12) {
                    PanelLabel("Daily average · by year")
                    if model.yearlySteps.count < 2 {
                        EmptyMetricState("Not enough history yet for a yearly view.")
                    } else {
                        BarRow(bars: model.yearlySteps.map { year in
                            BarRow.Bar(label: String(year.year), value: year.mean,
                                       isHighlighted: year.year == model.day.year)
                        }, height: 52)
                    }
                }
            }
        }
    }

    private var centreColumn: some View {
        VStack(spacing: 14) {
            CharacterStageView(state: .idle, mood: mood)
                .frame(maxHeight: .infinity)
            scorePanel
        }
    }

    /// Her expression comes from the day's real figures, never from randomness
    /// and never from the language model. A recovery score of 92 must not
    /// produce a sympathetic face, and an expression that flickers because a
    /// model sampled differently is worse than no expression at all.
    private var mood: CharacterMood {
        MoodResolver().mood(
            recovery: model.score?.components[.recovery],
            sleepHours: model.night.map { $0.asleepMinutes / 60 },
            activityPercentile: model.figures
                .first { $0.metric == "StepCount" }?.personalPercentile,
            hour: Calendar.current.component(.hour, from: .now))
    }

    private var scorePanel: some View {
        GlassPanel {
            HStack(spacing: 20) {
                if let score = model.score, let value = score.value, !score.isPartial {
                    RingGauge(fraction: value / 100,
                              label: String(Int(value.rounded())),
                              caption: "/ 100")
                        .frame(width: 116, height: 116)
                } else {
                    // Suppressed rather than shown low. The last day of an
                    // import is almost always partial, and a companion that
                    // reports collapsing health because you exported before
                    // lunch has spent its credibility.
                    RingGauge(fraction: 0, label: "—", caption: "IN PROGRESS")
                        .frame(width: 116, height: 116)
                }

                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        PanelLabel("Health score")
                        Spacer()
                        Text("percentile vs your own year")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textSecondary.opacity(0.7))
                    }

                    if let score = model.score {
                        ForEach(ScoreComponent.allCases, id: \.self) { component in
                            ScoreRow(component: component,
                                     value: score.components[component],
                                     weight: score.weights[component])
                        }
                    }
                }
            }
        }
    }

    private var rightColumn: some View {
        VStack(spacing: 14) {
            hrvPanel
            sleepPanel
        }
    }

    /// Names the real sample size rather than the window length.
    ///
    /// The baseline window is a year, but HRV only has 62 readings in it —
    /// labelling that "your 365-day mean" would imply a density of data that
    /// does not exist.
    private var baselineCaption: String {
        guard let hrv = model.figures.first(where: { $0.metric == "HeartRateVariabilitySDNN" })
        else { return "" }
        return "dashed line = your mean of \(hrv.baselineCount) readings"
    }

    private var hrvPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 11) {
                let hrv = model.figures.first { $0.metric == "HeartRateVariabilitySDNN" }
                HStack(alignment: .top) {
                    PanelLabel("Heart rate variability")
                    Spacer()
                    if let p = hrv?.personalPercentile {
                        Text("\(Int(p * 100))th percentile")
                            .font(.system(size: 10))
                            .foregroundStyle(p < 0.2 ? theme.accent : theme.textSecondary)
                    }
                }

                if let hrv {
                    MetricValue(String(format: "%.1f", hrv.value), unit: "ms", size: 26,
                                tint: (hrv.personalPercentile ?? 1) < 0.2 ? theme.accent : nil)
                    Sparkline(values: model.hrvWindow.map(\.value),
                              baseline: hrv.baselineMean,
                              highlightIndex: model.hrvWindow.count - 1)
                        .frame(height: 70)
                    Text(baselineCaption)
                        .font(.system(size: 9.5))
                        .foregroundStyle(theme.textSecondary.opacity(0.6))
                } else {
                    EmptyMetricState("No HRV reading for this day. Your Watch records it during sleep.")
                }
            }
        }
    }

    private var sleepPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    PanelLabel("Last night")
                    Spacer()
                    if let night = model.night {
                        // The era matters and is never hidden: an in-bed-only
                        // night is not the same measurement as a staged one.
                        Text(night.isStaged ? "STAGED" : "IN BED ONLY")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(night.isStaged ? theme.dataSeries[3] : theme.textSecondary)
                            .padding(.horizontal, 8).padding(.vertical, 2.5)
                            .background(Capsule().fill(
                                (night.isStaged ? theme.dataSeries[3] : theme.textSecondary)
                                    .opacity(0.12)))
                    }
                }

                if let night = model.night {
                    HStack(spacing: 16) {
                        StageDonut(
                            segments: stageSegments(night),
                            centre: "\(Int(night.asleepMinutes) / 60)h\(Int(night.asleepMinutes) % 60)",
                            caption: "asleep")
                            .frame(width: 96, height: 96)

                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(stageSegments(night)) { segment in
                                HStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(segment.color).frame(width: 7, height: 7)
                                    Text(segment.label)
                                        .font(.system(size: 11))
                                        .foregroundStyle(theme.textSecondary)
                                    Spacer()
                                    Text(Self.duration(segment.minutes))
                                        .font(.system(size: 11.5)).monospacedDigit()
                                        .foregroundStyle(theme.textPrimary.opacity(0.85))
                                }
                            }
                        }
                    }
                } else {
                    EmptyMetricState("No sleep recorded for this night.")
                }
            }
        }
    }

    private func stageSegments(_ night: DashboardViewModel.SleepNightSummary)
        -> [StageDonut.Segment] {
        guard night.isStaged else {
            return [.init(label: "In bed", minutes: night.asleepMinutes,
                          color: theme.dataSeries[0])]
        }
        return [
            .init(label: "Core",  minutes: night.coreMinutes,  color: theme.dataSeries[0]),
            .init(label: "Deep",  minutes: night.deepMinutes,  color: theme.dataSeries[1]),
            .init(label: "REM",   minutes: night.remMinutes,   color: theme.dataSeries[2]),
            .init(label: "Awake", minutes: night.awakeMinutes, color: theme.textSecondary.opacity(0.5)),
        ]
    }

    // MARK: Formatting

    static func format(_ figure: TrendEngine.Figure) -> String {
        switch figure.unit {
        case .count, .kilocalories, .minutes:
            return Int(figure.value.rounded()).formatted()
        default:
            return String(format: "%.1f", figure.value)
        }
    }

    static func duration(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        return total >= 60 ? "\(total / 60)h \(total % 60)m" : "\(total)m"
    }
}

/// One component of the score, with the weight actually applied to it.
///
/// The weight is on screen because a composite nobody can decompose is
/// decoration. If recovery is dragging the number down, that should be
/// readable at a glance rather than inferred.
private struct ScoreRow: View {
    @Environment(\.theme) private var theme

    let component: ScoreComponent
    let value: Double?
    let weight: Double?

    var body: some View {
        HStack(spacing: 11) {
            Text(component.rawValue.capitalized)
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 62, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.primary.opacity(0.16))
                    if let value {
                        Capsule().fill(tint)
                            .frame(width: geo.size.width * value / 100)
                    }
                }
            }
            .frame(height: 4)

            Text(value.map { String(Int($0.rounded())) } ?? "—")
                .font(.system(size: 12)).monospacedDigit()
                .foregroundStyle(value == nil ? theme.textSecondary : tint)
                .frame(width: 22, alignment: .trailing)

            Text(weight.map { String(format: "×%.2f", $0) } ?? "")
                .font(.system(size: 9.5))
                .foregroundStyle(theme.textSecondary.opacity(0.6))
                .frame(width: 34, alignment: .trailing)
        }
    }

    /// Colour carries the reading, so a weak component is visible without
    /// parsing the number.
    private var tint: Color {
        guard let value else { return theme.textSecondary }
        switch value {
        case 80...:  return theme.dataSeries[3]
        case 60..<80: return theme.secondary
        case 40..<60: return theme.dataSeries[4]
        default:      return theme.accent
        }
    }
}
