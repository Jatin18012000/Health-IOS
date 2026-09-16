import SwiftUI
import UniformTypeIdentifiers
import AURACore
import AURADesign
import AURAIngest

/// The way health data gets into AURA.
///
/// There is no HealthKit on macOS — no background sync, no permission sheet,
/// no live feed. A file you exported by hand is the entire supply chain, which
/// makes this screen load-bearing in a way an import screen usually isn't. It
/// is built to be dropped on: the file the Health app produces is a `.zip`,
/// and the shortest honest path from that file to a dashboard is to let
/// someone drag it here.
public struct ImportView: View {
    @Environment(\.theme) private var theme
    @State private var model: ImportViewModel
    @State private var showingPicker = false
    @State private var isTargeted = false

    /// Called when the person wants to leave for the dashboard after a
    /// successful import.
    private let onDone: () -> Void

    public init(model: ImportViewModel, onDone: @escaping () -> Void = {}) {
        _model = State(wrappedValue: model)
        self.onDone = onDone
    }

    public var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            AmbientField()

            VStack(spacing: 20) {
                header

                switch model.phase {
                case .idle:
                    dropZone
                    instructions
                case .needsExpanding(let url):
                    expansionPrompt(url)
                case .preparing, .parsing, .rebuilding:
                    progress
                case .finished(let outcome):
                    ImportSummary(outcome: outcome, onDone: onDone) { model.reset() }
                case .failed(let message):
                    failure(message)
                }

                Spacer(minLength: 0)
            }
            .padding(30)
            .frame(maxWidth: 620)
        }
        .fileImporter(isPresented: $showingPicker,
                      allowedContentTypes: [.zip, .xml, .folder]) { result in
            if case .success(let url) = result { model.start(url) }
        }
        // Dropping a folder or a zip is the same gesture as picking one, so it
        // is refused in exactly the same cases: while an import is running.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, !model.isRunning else { return false }
            model.start(url)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: 6) {
            Text("Import your health data")
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundStyle(theme.textPrimary)
            Text("Everything stays on this Mac. Nothing is uploaded, now or ever.")
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.top, 10)
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: isTargeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(isTargeted ? theme.primary : theme.textSecondary)

            VStack(spacing: 4) {
                Text("Drop your export here")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                Text("the apple_health_export folder, or export.xml inside it")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
            }

            Button("Choose a file…") { showingPicker = true }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.primary)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(Capsule().fill(theme.primary.opacity(0.14)))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .background {
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                .fill(theme.surface.opacity(isTargeted ? 1 : 0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                        .strokeBorder(
                            isTargeted ? theme.primary : theme.surfaceStroke,
                            style: StrokeStyle(lineWidth: 1, dash: isTargeted ? [] : [5, 4]))
                }
        }
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }

    private var instructions: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                PanelLabel("How to get the file")
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.primary)
                            .frame(width: 15, height: 15)
                            .background(Circle().fill(theme.primary.opacity(0.15)))
                        Text(step)
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("The export takes a few minutes to prepare on the phone, and four years of data is roughly 300 MB.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.textSecondary.opacity(0.7))
                    .padding(.top, 2)
            }
        }
    }

    private static let steps = [
        "On your iPhone, open Health and tap your profile picture, top right.",
        "Scroll down and tap Export All Health Data, then Export.",
        "AirDrop the file to this Mac, or save it to Files and copy it across.",
        "Double-click export.zip to unzip it, then drop the folder above.",
        "Re-importing later is safe — AURA only adds records it doesn't have.",
    ]

    /// A zip is what the Health app produces, so it is the most likely thing
    /// to be dropped here — and the one thing AURA deliberately cannot open
    /// itself. Explaining that in one screen with one button beats an error.
    private func expansionPrompt(_ url: URL) -> some View {
        GlassPanel(padding: 26) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    Image(systemName: "archivebox")
                        .foregroundStyle(theme.secondary)
                    Text("That's still zipped")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                }
                Text("macOS will expand “\(url.lastPathComponent)” into a folder next to it. Drop that folder here and the import starts.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("AURA doesn't unzip files itself — doing so would mean either an extra dependency or giving the app permission to launch other programs, and neither is worth one double-click.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.textSecondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button("Expand it now") { model.expandWithFinder() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.background)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Capsule().fill(theme.primary))

                    Button("Never mind") { model.reset() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                        .padding(.vertical, 8)
                }
                .padding(.top, 2)
            }
        }
    }

    private var progress: some View {
        GlassPanel(padding: 26) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small).tint(theme.primary)
                    Text(phaseTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                }

                if case .parsing(let fraction, let records) = model.phase {
                    ProgressView(value: fraction).tint(theme.primary)
                    HStack {
                        Text("\(records.formatted()) records read")
                        Spacer()
                        Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    }
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(theme.textSecondary)
                } else {
                    ProgressView().progressViewStyle(.linear).tint(theme.primary)
                }

                Text(phaseDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var phaseTitle: String {
        switch model.phase {
        case .preparing(let name): "Opening \(name)"
        case .parsing:             "Reading your export"
        case .rebuilding(let days):
            "Rebuilding \(days.formatted()) \(days == 1 ? "day" : "days")"
        default:                   ""
        }
    }

    private var phaseDetail: String {
        switch model.phase {
        case .preparing:
            "Expanding the archive. A four-year export can take a minute."
        case .parsing:
            "Records are written as they're read, so this can be left alone."
        case .rebuilding:
            "Recomputing daily totals for the days this import touched — deduplicating across every device you wore."
        default:
            ""
        }
    }

    private func failure(_ message: String) -> some View {
        GlassPanel(padding: 26) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(theme.accent)
                    Text("The import didn't finish")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                }
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Text("Nothing was left half-written: each batch is its own transaction, so the data you already had is untouched.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.textSecondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try another file") { model.reset() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.primary)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(theme.primary.opacity(0.14)))
            }
        }
    }
}

/// What the import actually did, in counts.
///
/// The number that needs explaining is `duplicates`. Every Health export
/// contains the person's entire history, so the second import of an
/// overlapping export is ~99% records the store already had. An importer that
/// reported that as a warning would be calling its own idempotency a fault,
/// and one that hid it would be hiding the evidence that it worked.
private struct ImportSummary: View {
    @Environment(\.theme) private var theme
    let outcome: ImportSession.Outcome
    let onDone: () -> Void
    let onAgain: () -> Void

    @State private var showingIssues = false

    var body: some View {
        VStack(spacing: 14) {
            GlassPanel(padding: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 9) {
                        Image(systemName: "checkmark.seal")
                            .foregroundStyle(theme.secondary)
                        Text(headline)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(theme.textPrimary)
                    }

                    HStack(alignment: .top, spacing: 26) {
                        figure("Read", outcome.recordsParsed)
                        figure("Added", outcome.samplesStored)
                        figure("Already had", outcome.duplicates)
                    }

                    if outcome.duplicates > outcome.samplesStored {
                        Text("Most of this export was already in your store. That's expected — every export contains your whole history, and AURA keeps one copy of each record.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let range = outcome.daysAffected {
                        Divider().overlay(theme.surfaceStroke)
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10))
                                .foregroundStyle(theme.textSecondary)
                            Text("\(range.start.date().formatted(.dateTime.day().month().year())) – \(range.end.date().formatted(.dateTime.day().month().year()))")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.textSecondary)
                            Spacer()
                            Text("\(outcome.duration.formatted(.number.precision(.fractionLength(1))))s")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(theme.textSecondary.opacity(0.7))
                        }
                    }
                }
            }

            if outcome.hasIssues { issues }

            HStack(spacing: 10) {
                Button("Open the dashboard", action: onDone)
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.background)
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(Capsule().fill(theme.primary))

                Button("Import another", action: onAgain)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 14).padding(.vertical, 9)
            }
        }
    }

    private var headline: String {
        outcome.samplesStored == 0
            ? "Nothing new in this export"
            : "\(outcome.samplesStored.formatted()) new records imported"
    }

    private func figure(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            MetricValue(value.formatted(), size: 19)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.textSecondary.opacity(0.75))
        }
    }

    /// Surfaced rather than swallowed.
    ///
    /// Almost every real export has some: metrics AURA has no catalog entry
    /// for, mostly. Collapsed by default because the list is long and none of
    /// it is actionable; present at all because an importer that silently
    /// drops 3% of someone's data is worse than one that fails.
    private var issues: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    showingIssues.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: showingIssues ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9))
                        Text("\(outcome.rejected.values.reduce(0, +).formatted()) records skipped, in \(outcome.rejected.count) \(outcome.rejected.count == 1 ? "category" : "categories")")
                            .font(.system(size: 11))
                        Spacer()
                    }
                    .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(.plain)

                if showingIssues {
                    // Scrolls rather than clips: a real export produces dozens
                    // of unmapped-metric lines, and a truncated list of them is
                    // indistinguishable from a short one.
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(outcome.rejected.sorted { $0.value > $1.value }, id: \.key) { entry in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(entry.value.formatted())
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(theme.textSecondary.opacity(0.7))
                                        .frame(width: 58, alignment: .trailing)
                                    Text(entry.key)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(theme.textSecondary)
                                        .textSelection(.enabled)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 190)
                }
            }
        }
    }
}
