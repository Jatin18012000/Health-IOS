import SwiftUI

/// The card every dashboard section sits in.
///
/// One panel style, used everywhere. The neon-glass look lives here and nowhere
/// else, so changing it is one edit rather than forty.
public struct GlassPanel<Content: View>: View {
    @Environment(\.theme) private var theme

    private let padding: CGFloat
    private let content: Content

    public init(padding: CGFloat = 17, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                    .fill(theme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                            .strokeBorder(theme.surfaceStroke, lineWidth: 1)
                    }
            }
    }
}

/// A section label. Small, wide-tracked, quiet — it names the panel without
/// competing with the number inside it.
public struct PanelLabel: View {
    @Environment(\.theme) private var theme
    private let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.0)
            .foregroundStyle(theme.textSecondary.opacity(0.75))
    }
}

/// A figure and its unit, sharing a baseline.
public struct MetricValue: View {
    @Environment(\.theme) private var theme

    private let value: String
    private let unit: String
    private let size: CGFloat
    private let tint: Color?

    public init(_ value: String, unit: String = "", size: CGFloat = 20, tint: Color? = nil) {
        self.value = value
        self.unit = unit
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: size, weight: .medium, design: .rounded))
                // Tabular figures: without them a changing number jitters its
                // own layout, which on a live dashboard is constant motion in
                // the corner of your eye.
                .monospacedDigit()
                .foregroundStyle(tint ?? theme.textPrimary)
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: max(10, size * 0.48)))
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }
}

/// What a card shows when there is nothing honest to put in it.
///
/// Deliberately not a zero, not a dash, and not a flat line through two points.
/// The reference export has three body-mass readings across four years; drawing
/// a trend through those would be inventing one.
public struct EmptyMetricState: View {
    @Environment(\.theme) private var theme

    private let reason: String

    public init(_ reason: String) { self.reason = reason }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.dotted")
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary.opacity(0.5))
            Text(reason)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

/// Marks a value that went through multi-source deduplication.
///
/// Most health apps hide provenance. This one has a specific reason not to:
/// on a day both an iPhone and a Watch were worn, the raw sum can be nearly
/// twice the truth, and a figure you can't interrogate is a figure you can't
/// trust.
public struct ProvenanceBadge: View {
    @Environment(\.theme) private var theme

    private let sourceCount: Int
    private let rawTotal: Double?

    public init(sourceCount: Int, rawTotal: Double? = nil) {
        self.sourceCount = sourceCount
        self.rawTotal = rawTotal
    }

    public var body: some View {
        if sourceCount > 1 {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(sourceCount) devices overlapped — deduplicated.")
                        .foregroundStyle(theme.textSecondary)
                    if let raw = rawTotal {
                        Text("Raw sum would read \(Int(raw).formatted()).")
                            .foregroundStyle(theme.textSecondary.opacity(0.7))
                    }
                }
                .font(.system(size: 10))
            }
        }
    }
}

/// The soft coloured glow behind a full screen.
///
/// Lives here rather than in one view because every full-screen surface — the
/// dashboard, the importer, anything added later — needs the same background,
/// and two copies of it drift the moment a theme changes.
public struct AmbientField: View {
    @Environment(\.theme) private var theme

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [theme.primary.opacity(0.20), .clear],
                                         center: .center, startRadius: 0, endRadius: 350))
                    .frame(width: 700, height: 700)
                    .position(x: geo.size.width * 0.42, y: -60)
                Circle()
                    .fill(RadialGradient(colors: [theme.secondary.opacity(0.12), .clear],
                                         center: .center, startRadius: 0, endRadius: 310))
                    .frame(width: 620, height: 620)
                    .position(x: geo.size.width * 0.85, y: geo.size.height + 80)
            }
        }
        .allowsHitTesting(false)
    }
}
