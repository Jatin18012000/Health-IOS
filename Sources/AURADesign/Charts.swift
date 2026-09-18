import SwiftUI

/// The chart vocabulary. Four marks, used consistently.
///
/// Hand-drawn with `Shape` and `Canvas` rather than Swift Charts. Not dogma —
/// Swift Charts is the right default — but these four are small, fixed, and
/// need a neon treatment (glow, gradient strokes, rounded caps) that is more
/// work to coax out of a charting library than to draw directly.

// MARK: - Ring

/// The score ring.
public struct RingGauge: View {
    @Environment(\.theme) private var theme

    private let fraction: Double
    private let lineWidth: CGFloat
    private let label: String
    private let caption: String?

    public init(fraction: Double, lineWidth: CGFloat = 9,
                label: String, caption: String? = nil) {
        self.fraction = min(max(fraction, 0), 1)
        self.lineWidth = lineWidth
        self.label = label
        self.caption = caption
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(theme.primary.opacity(0.16), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(
                        colors: [theme.secondary, theme.primary, theme.accent],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: theme.primary.opacity(0.45), radius: theme.glowRadius * 0.4)
                // The ring animates to a new value rather than jumping, so a
                // refresh reads as the number changing rather than the view
                // being replaced.
                .animation(.easeOut(duration: 0.6), value: fraction)

            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                if let caption {
                    Text(caption)
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
    }
}

// MARK: - Sparkline

public struct Sparkline: View {
    @Environment(\.theme) private var theme

    private let values: [Double]
    private let baseline: Double?
    private let highlightIndex: Int?
    private let tint: Color?

    public init(values: [Double], baseline: Double? = nil,
                highlightIndex: Int? = nil, tint: Color? = nil) {
        self.values = values
        self.baseline = baseline
        self.highlightIndex = highlightIndex
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { geo in
            let stroke = tint ?? theme.secondary
            let points = Self.points(values, in: geo.size, baseline: baseline)

            ZStack {
                // The person's own baseline, drawn as a reference rather than a
                // target — there is no population norm on this chart.
                if let baseline, let y = Self.y(for: baseline, values: values,
                                                size: geo.size, baseline: baseline) {
                    Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: geo.size.width, y: y)) }
                        .stroke(theme.primary.opacity(0.3),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(stroke, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .shadow(color: stroke.opacity(0.4), radius: 4)

                if let i = highlightIndex, points.indices.contains(i) {
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 8, height: 8)
                        .position(points[i])
                }
            }
        }
    }

    // `nonisolated`: `Sparkline` conforms to `View`, and the newest SDK makes
    // a `View`-conforming type globally `@MainActor`-isolated by default --
    // its whole surface, not just `body`, even for a static func that never
    // touches UI state. `DesignTests.swift` calls these three directly to
    // pin the geometry formula (see that file's own doc comment), and
    // Swift Testing runs test functions off the main actor, so the runtime
    // isolation check trapped with SIGTRAP
    // (swift_task_checkIsolatedSwift -> dispatch_assert_queue_fail) the
    // moment a test called `Sparkline.points` from a non-MainActor executor
    // -- confirmed from the crash report's thread backtrace, not guessed.
    // `body` calls these synchronously today and keeps doing so: a
    // `nonisolated` sync function is callable without `await` from any
    // actor, MainActor included.
    nonisolated static func points(_ values: [Double], in size: CGSize, baseline: Double?) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let (lo, hi) = bounds(values, baseline: baseline)
        let span = max(hi - lo, 0.0001)
        let step = size.width / CGFloat(values.count - 1)
        let inset: CGFloat = 5
        return values.enumerated().map { i, v in
            let t = (v - lo) / span
            return CGPoint(x: CGFloat(i) * step,
                           y: size.height - inset - CGFloat(t) * (size.height - inset * 2))
        }
    }

    nonisolated static func y(for value: Double, values: [Double], size: CGSize, baseline: Double?) -> CGFloat? {
        guard values.count > 1 else { return nil }
        let (lo, hi) = bounds(values, baseline: baseline)
        let span = max(hi - lo, 0.0001)
        let inset: CGFloat = 5
        return size.height - inset - CGFloat((value - lo) / span) * (size.height - inset * 2)
    }

    /// Include the baseline in the extent, so the reference line can never fall
    /// outside the drawn area and silently disappear.
    nonisolated static func bounds(_ values: [Double], baseline: Double?) -> (Double, Double) {
        var all = values
        if let baseline { all.append(baseline) }
        return (all.min() ?? 0, all.max() ?? 1)
    }
}

// MARK: - Bars

public struct BarRow: View {
    @Environment(\.theme) private var theme

    public struct Bar: Identifiable {
        public let id = UUID()
        public let label: String
        public let value: Double
        public let isHighlighted: Bool

        public init(label: String, value: Double, isHighlighted: Bool = false) {
            self.label = label
            self.value = value
            self.isHighlighted = isHighlighted
        }
    }

    private let bars: [Bar]
    private let height: CGFloat

    public init(bars: [Bar], height: CGFloat = 68) {
        self.bars = bars
        self.height = height
    }

    public var body: some View {
        let peak = bars.map(\.value).max() ?? 1

        HStack(alignment: .bottom, spacing: 7) {
            ForEach(bars) { bar in
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(bar.isHighlighted ? theme.primary : theme.primary.opacity(0.34))
                        .frame(height: max(2, height * (peak > 0 ? bar.value / peak : 0)))
                    Text(bar.label)
                        .font(.system(size: 9))
                        .foregroundStyle(theme.textSecondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height + 18, alignment: .bottom)
    }
}

// MARK: - Donut

/// Sleep stages. Segments in a fixed order so the colours mean the same thing
/// every night.
public struct StageDonut: View {
    @Environment(\.theme) private var theme

    public struct Segment: Identifiable {
        public let id = UUID()
        public let label: String
        public let minutes: Double
        public let color: Color

        public init(label: String, minutes: Double, color: Color) {
            self.label = label
            self.minutes = minutes
            self.color = color
        }
    }

    private let segments: [Segment]
    private let centre: String
    private let caption: String

    public init(segments: [Segment], centre: String, caption: String) {
        self.segments = segments
        self.centre = centre
        self.caption = caption
    }

    public var body: some View {
        let total = segments.reduce(0) { $0 + $1.minutes }

        ZStack {
            if total > 0 {
                ForEach(Array(offsets(total: total).enumerated()), id: \.offset) { i, span in
                    Circle()
                        .trim(from: span.start, to: span.end)
                        .stroke(segments[i].color,
                                style: StrokeStyle(lineWidth: 10, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
            } else {
                Circle().stroke(theme.primary.opacity(0.14), lineWidth: 10)
            }

            VStack(spacing: 1) {
                Text(centre)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                Text(caption)
                    .font(.system(size: 9))
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private func offsets(total: Double) -> [(start: Double, end: Double)] {
        var cursor = 0.0
        return segments.map { segment in
            let fraction = segment.minutes / total
            defer { cursor += fraction }
            return (cursor, cursor + fraction)
        }
    }
}
