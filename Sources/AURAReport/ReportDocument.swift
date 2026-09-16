import SwiftUI
import AURACore

/// The report, laid out for paper.
///
/// Light, serif-adjacent, high contrast — the opposite of the dashboard.
/// Deliberately: a neon-on-black PDF is unreadable printed, and this is the one
/// thing in the app that leaves the machine and lands in someone else's hands.
struct ReportDocument: View {

    let report: HealthReport

    /// A4 at 72 pt/inch, which is what `ImageRenderer` writes into a PDF page.
    static let pageSize = CGSize(width: 595, height: 842)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            Divider()
            vitals
            sleepSection
            if !report.periods.isEmpty { periodsSection }
            Spacer(minLength: 0)
            limitations
        }
        .padding(44)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height,
               alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(.black)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Personal health summary")
                .font(.system(size: 19, weight: .semibold))
            Text("\(report.range.start.description) to \(report.range.end.description)"
               + " · \(report.totalDays) days with data")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("Prepared \(report.generatedOn.formatted(date: .abbreviated, time: .shortened))"
               + (report.sources.isEmpty ? "" : " · sources: \(report.sources.joined(separator: ", "))"))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private var vitals: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Measurements").font(.system(size: 13, weight: .semibold))

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    Text("Metric").gridColumnAlignment(.leading)
                    Text("Latest").gridColumnAlignment(.trailing)
                    Text("30-day mean").gridColumnAlignment(.trailing)
                    Text("12-month mean").gridColumnAlignment(.trailing)
                    // The column that keeps the table honest.
                    Text("Readings").gridColumnAlignment(.trailing)
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)

                Divider().gridCellUnsizedAxes(.horizontal)

                ForEach(report.rows) { row in
                    GridRow {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.label).font(.system(size: 10.5))
                            if let day = row.latestDay {
                                Text("last \(day.description)")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        cell(row.latest, row.unit)
                        cell(row.mean30, row.unit)
                        cell(row.mean365, row.unit)
                        Text("\(row.coverage365)")
                            .font(.system(size: 10)).monospacedDigit()
                            // Flagged rather than hidden: a mean over eleven
                            // readings is not a trend and should not look like one.
                            .foregroundStyle(row.coverage365 < 30 ? .red : .primary)
                    }
                }
            }
        }
    }

    private func cell(_ value: Double?, _ unit: String) -> some View {
        Text(value.map { format($0) + " " + unit } ?? "—")
            .font(.system(size: 10)).monospacedDigit()
    }

    private func format(_ value: Double) -> String {
        value >= 100 ? String(Int(value.rounded())) : String(format: "%.1f", value)
    }

    private var sleepSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sleep").font(.system(size: 13, weight: .semibold))

            // Two rows, never one average. Combining them would invent a figure
            // that describes neither.
            if report.sleep.stagedNights > 0 {
                line("Measured stages", "\(report.sleep.stagedNights) nights",
                     detail: [
                        report.sleep.meanAsleepStaged.map { "mean \(hours($0)) asleep" },
                        report.sleep.meanEfficiencyStaged.map {
                            String(format: "mean efficiency %.0f%%", $0) },
                     ].compactMap { $0 }.joined(separator: ", "))
            }
            if report.sleep.inBedOnlyNights > 0 {
                line("Time in bed only", "\(report.sleep.inBedOnlyNights) nights",
                     detail: report.sleep.meanAsleepInBedOnly.map {
                        "mean \(hours($0)) in bed — not a measure of sleep" } ?? "")
            }
            if report.sleep.stagedNights == 0 && report.sleep.inBedOnlyNights == 0 {
                Text("No sleep recorded in this period.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private var periodsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Periods the subject marked as unusual")
                .font(.system(size: 13, weight: .semibold))
            ForEach(report.periods) { period in
                line(period.kind,
                     "\(period.range.start.description) – \(period.range.end.description)",
                     detail: "\(period.dayCount) days"
                           + (period.note.map { " · \($0)" } ?? ""))
            }
        }
    }

    private func line(_ title: String, _ value: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.system(size: 10.5, weight: .medium)).frame(width: 130, alignment: .leading)
            Text(value).font(.system(size: 10)).monospacedDigit()
            Text(detail).font(.system(size: 9)).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func hours(_ minutes: Double) -> String {
        "\(Int(minutes) / 60)h \(Int(minutes) % 60)m"
    }

    private var limitations: some View {
        VStack(alignment: .leading, spacing: 5) {
            Divider()
            Text("How to read this").font(.system(size: 10, weight: .semibold))
            ForEach(Array(report.limitations.enumerated()), id: \.offset) { _, note in
                Text("• " + note)
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Generated by AURA, a personal health tool. It contains no clinical "
               + "interpretation and is not a diagnostic document.")
                .font(.system(size: 8.5))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }
}

/// Renders the report to a PDF.
@MainActor
public enum ReportExporter {

    /// Write `report` to `url` as a single-page PDF.
    ///
    /// `ImageRenderer` rather than hand-drawn Core Graphics: the layout is a
    /// SwiftUI view, so it is readable, and text stays selectable in the output.
    public static func writePDF(_ report: HealthReport, to url: URL) throws {
        let renderer = ImageRenderer(content: ReportDocument(report: report))
        renderer.proposedSize = ProposedViewSize(ReportDocument.pageSize)

        var box = CGRect(origin: .zero, size: ReportDocument.pageSize)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else {
            throw ReportError.cannotWrite(url)
        }

        renderer.render { _, draw in
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
        }
    }

    public enum ReportError: Error, Sendable {
        case cannotWrite(URL)
    }
}
