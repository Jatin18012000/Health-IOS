import SwiftUI
import AppKit
import AURACore
import AURADesign
import AURAStore

/// Preferences, and the two ways data leaves this Mac on purpose.
///
/// Both of those — the clinical PDF and the encrypted backup — are the only
/// paths out of an app that otherwise has none, so they are together on one
/// screen, each saying plainly what it does and does not contain.
public struct SettingsView: View {
    @Environment(\.theme) private var theme
    @State private var model: SettingsViewModel
    private let preferences: Preferences
    private let status: [StatusLine]

    public init(model: SettingsViewModel,
                preferences: Preferences,
                status: [StatusLine] = []) {
        _model = State(wrappedValue: model)
        self.preferences = preferences
        self.status = status
    }

    /// One component and whether it is actually working, as opposed to
    /// configured. The distinction matters: the language model, the voice and
    /// the character rig all have honest "not here yet" states.
    public struct StatusLine: Identifiable {
        public let id = UUID()
        public let label: String
        public let detail: String
        public let isReady: Bool
        public init(label: String, detail: String, isReady: Bool) {
            self.label = label
            self.detail = detail
            self.isReady = isReady
        }
    }

    public var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            AmbientField()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Settings")
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.textPrimary)

                    if let note = model.note { noteBanner(note) }

                    appearance
                    goals
                    morningBrief
                    report
                    backup
                    if !status.isEmpty { components }
                    storage
                }
                .padding(26)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Appearance

    private var appearance: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                PanelLabel("Appearance")
                HStack(spacing: 10) {
                    ForEach(Theme.all) { option in
                        Button { preferences.theme = option } label: {
                            VStack(spacing: 6) {
                                swatch(option)
                                Text(option.name)
                                    .font(.system(size: 10))
                                    .foregroundStyle(preferences.theme.id == option.id
                                                     ? theme.textPrimary : theme.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func swatch(_ option: Theme) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(option.background)
            .frame(width: 66, height: 40)
            .overlay {
                HStack(spacing: 4) {
                    Circle().fill(option.primary).frame(width: 9, height: 9)
                    Circle().fill(option.secondary).frame(width: 9, height: 9)
                    Circle().fill(option.accent).frame(width: 9, height: 9)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(preferences.theme.id == option.id
                                  ? theme.primary : theme.surfaceStroke,
                                  lineWidth: preferences.theme.id == option.id ? 2 : 1)
            }
    }

    // MARK: Goals

    private var goals: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                PanelLabel("Goals")
                Text("A goal is a number you picked. It never moves a percentile, a baseline or the composite score — those describe you, and letting a target bend them would make them flattering instead of true.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.textSecondary.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)

                stepper("Daily steps",
                        value: Binding(get: { preferences.goals.dailySteps },
                                       set: { preferences.goals.dailySteps = $0 }),
                        range: 1_000...30_000, step: 500)

                // Both of these are optional in `Goals`, and the switch is how
                // "not set" stays representable. Showing a plausible default
                // for a goal nobody chose would put a number on screen that
                // nothing is measured against.
                optionalStepper(
                    "Exercise minutes", unset: 30,
                    value: Binding(get: { preferences.goals.dailyExerciseMinutes },
                                   set: { preferences.goals.dailyExerciseMinutes = $0 }),
                    range: 5...240, step: 5,
                    format: { $0.formatted() })

                optionalStepper(
                    "Sleep hours", unset: 8,
                    value: Binding(get: { preferences.goals.nightlySleepHours },
                                   set: { preferences.goals.nightlySleepHours = $0 }),
                    range: 4...12, step: 0.25,
                    format: { $0.formatted(.number.precision(.fractionLength(0...2))) })
            }
        }
    }

    private func stepper(_ label: String, value: Binding<Int>,
                         range: ClosedRange<Int>, step: Int) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
            Spacer()
            Text(value.wrappedValue.formatted())
                .font(.system(size: 12, design: .rounded).monospacedDigit())
                .foregroundStyle(theme.textPrimary)
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
        }
    }

    /// A goal that can be switched off entirely.
    ///
    /// `nil` is a real state — `Goals.progress(for:)` reports nothing for a
    /// target nobody set — so the row shows "Off" rather than a number, and the
    /// stepper only appears once the goal exists.
    private func optionalStepper<V: Strideable>(
        _ label: String, unset: V, value: Binding<V?>,
        range: ClosedRange<V>, step: V.Stride,
        format: @escaping (V) -> String
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
            Spacer()
            if let current = value.wrappedValue {
                Text(format(current))
                    .font(.system(size: 12, design: .rounded).monospacedDigit())
                    .foregroundStyle(theme.textPrimary)
                Stepper("",
                        value: Binding(get: { current },
                                       set: { value.wrappedValue = $0 }),
                        in: range, step: step)
                    .labelsHidden()
            } else {
                Text("Off")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary.opacity(0.7))
            }
            Toggle("", isOn: Binding(
                get: { value.wrappedValue != nil },
                set: { value.wrappedValue = $0 ? unset : nil }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .tint(theme.primary)
        }
    }

    // MARK: Morning brief

    private var morningBrief: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                PanelLabel("Morning brief")
                Toggle(isOn: Binding(get: { preferences.morningBriefEnabled },
                                     set: { preferences.morningBriefEnabled = $0 })) {
                    Text("Let her speak first, once a day")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textPrimary)
                }
                .toggleStyle(.switch)
                .tint(theme.primary)

                if preferences.morningBriefEnabled {
                    HStack {
                        Text("Not before")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textSecondary)
                        Spacer()
                        Text(String(format: "%02d:00", preferences.morningBriefHour))
                            .font(.system(size: 12, design: .rounded).monospacedDigit())
                            .foregroundStyle(theme.textPrimary)
                        Stepper("",
                                value: Binding(get: { preferences.morningBriefHour },
                                               set: { preferences.morningBriefHour = $0 }),
                                in: 4...11)
                            .labelsHidden()
                    }
                }

                Text("Most mornings there is nothing worth interrupting for, and on those she says nothing. That silence is the feature — a brief every day trains you to ignore the one that matters.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.textSecondary.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Report

    private var report: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                PanelLabel("Report for a clinician")
                Text("Measurements, their averages and how many days each is based on. No score, no interpretation, no reference ranges — a doctor wants the figures, and a model's opinion about them is unattributable in a consultation.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.textSecondary.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Picker("", selection: $model.reportMonths) {
                        Text("3 months").tag(3)
                        Text("6 months").tag(6)
                        Text("12 months").tag(12)
                        Text("24 months").tag(24)
                    }
                    .labelsHidden()
                    .frame(width: 130)

                    action("Export PDF…", busy: model.job == .buildingReport) {
                        Task { await model.exportReport() }
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: Backup

    private var backup: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                PanelLabel("Encrypted backup")
                Text("FileVault protects this data while it is on this Mac. A backup leaves it, so it carries its own encryption and is useless without the passphrase. There is no recovery — none is possible, which is the point.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.textSecondary.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)

                if model.restorePending {
                    restoreStaged
                } else {
                    SecureField("Passphrase", text: $model.passphrase)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    SecureField("Passphrase again", text: $model.confirmPassphrase)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))

                    if let problem = model.passphraseProblem {
                        Text(problem)
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.accent)
                    }

                    HStack(spacing: 10) {
                        action("Back up…", busy: model.job == .writingBackup,
                               enabled: model.passphraseProblem == nil
                                        && model.passphrase.count >= Backup.minimumPassphrase
                                        && model.passphrase == model.confirmPassphrase) {
                            Task { await model.writeBackup() }
                        }
                        action("Restore…", busy: model.job == .restoring,
                               prominent: false,
                               enabled: !model.passphrase.isEmpty) {
                            Task { await model.restore() }
                        }
                        Spacer()
                        if let last = preferences.lastBackup {
                            Text("Last: \(last.formatted(date: .abbreviated, time: .omitted))")
                                .font(.system(size: 10.5))
                                .foregroundStyle(theme.textSecondary.opacity(0.7))
                        } else {
                            Text("Never backed up")
                                .font(.system(size: 10.5))
                                .foregroundStyle(theme.accent.opacity(0.9))
                        }
                    }
                }
            }
        }
    }

    /// A restore is staged, never applied live: both databases are open with
    /// WAL journaling and writing over them underneath an open connection
    /// corrupts them silently.
    private var restoreStaged: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(theme.secondary)
                Text("A restore is waiting for a relaunch")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
            }
            Text("Nothing has changed yet. AURA replaces its databases on the next launch, before it opens either of them — overwriting a live SQLite file corrupts it, and silently.")
                .font(.system(size: 10.5))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                action("Quit AURA") { NSApplication.shared.terminate(nil) }
                action("Cancel the restore", prominent: false) { model.cancelRestore() }
            }
        }
    }

    // MARK: Components and storage

    private var components: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 9) {
                PanelLabel("Components")
                ForEach(status) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(line.isReady ? theme.dataSeries[3] : theme.textSecondary)
                            .frame(width: 6, height: 6)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(line.label)
                                .font(.system(size: 11.5))
                                .foregroundStyle(theme.textPrimary)
                            Text(line.detail)
                                .font(.system(size: 10))
                                .foregroundStyle(theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private var storage: some View {
        let onDisk = model.storageOnDisk()
        return GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                PanelLabel("On this Mac")
                HStack {
                    Text("Health data")
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                    Text(SettingsViewModel.bytes(onDisk.health))
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(theme.textPrimary)
                }
                HStack {
                    Text("Memory")
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                    Text(SettingsViewModel.bytes(onDisk.memory))
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(theme.textPrimary)
                }
                Text(AppContainer.folder.path)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(theme.textSecondary.opacity(0.6))
                    .textSelection(.enabled)
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppContainer.storeURL])
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(theme.primary)
            }
        }
    }

    // MARK: Bits

    private func noteBanner(_ note: SettingsViewModel.Note) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: note.isError ? "exclamationmark.triangle" : "checkmark.circle")
                .foregroundStyle(note.isError ? theme.accent : theme.secondary)
            Text(note.text)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer()
            Button { model.dismissNote() } label: {
                Image(systemName: "xmark").font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.textSecondary)
        }
        .padding(13)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill((note.isError ? theme.accent : theme.secondary).opacity(0.13))
        }
    }

    private func action(_ title: String, busy: Bool = false, prominent: Bool = true,
                        enabled: Bool = true,
                        run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 6) {
                if busy { ProgressView().controlSize(.mini) }
                Text(title)
            }
            .font(.system(size: 12, weight: prominent ? .semibold : .medium))
            .foregroundStyle(prominent ? theme.background : theme.primary)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(prominent ? theme.primary : theme.primary.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .disabled(busy || !enabled || model.isBusy)
        .opacity(enabled && !model.isBusy ? 1 : 0.5)
    }
}
