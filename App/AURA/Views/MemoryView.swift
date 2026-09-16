import SwiftUI
import AURACore
import AURADesign
import AURAMemory

/// What she remembers, and your control over it.
///
/// This screen exists because the alternative is worse. A companion that
/// accumulates conclusions about you silently is unsettling however good the
/// conclusions are; one whose memory you can read, correct and delete is not.
/// Everything she believes about you is on this page.
public struct MemoryView: View {
    @Environment(\.theme) private var theme
    @State private var model: MemoryViewModel

    public init(model: MemoryViewModel) {
        _model = State(wrappedValue: model)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                if !model.proposed.isEmpty { proposals }
                confirmed
                annotations
            }
            .padding(30)
        }
        .background(theme.background)
        .task { await model.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Memory")
                .font(.system(size: 23, weight: .medium, design: .rounded))
                .foregroundStyle(theme.textPrimary)
            Text("Everything she knows about you beyond the numbers. Yours to edit.")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.textSecondary)
        }
    }

    // MARK: Proposals

    /// Shown first, because an unanswered question is the only thing on this
    /// page that needs you.
    private var proposals: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PanelLabel("Should she remember this?")
                Text("\(model.proposed.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.background)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(theme.accent))
            }

            ForEach(model.proposed) { fact in
                GlassPanel {
                    VStack(alignment: .leading, spacing: 11) {
                        Text(fact.text)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.textPrimary)

                        if let quote = fact.sourceQuote {
                            // What you actually said, so you can judge whether
                            // she read it correctly rather than trusting her
                            // paraphrase of you.
                            Text("you said: \u{201C}\(quote)\u{201D}")
                                .font(.system(size: 11))
                                .italic()
                                .foregroundStyle(theme.textSecondary)
                        }

                        HStack(spacing: 8) {
                            Button("Remember") { Task { await model.confirm(fact) } }
                                .buttonStyle(PillButton(tint: theme.dataSeries[3]))
                            Button("No") { Task { await model.reject(fact) } }
                                .buttonStyle(PillButton(tint: theme.textSecondary))
                            Spacer()
                            Text(fact.kind.rawValue)
                                .font(.system(size: 10))
                                .foregroundStyle(theme.textSecondary.opacity(0.7))
                        }
                    }
                }
            }
        }
    }

    // MARK: Confirmed

    private var confirmed: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelLabel("She remembers")

            if model.confirmed.isEmpty {
                EmptyMetricState("Nothing yet. Tell her something about your life and "
                               + "she will ask whether to keep it.")
            } else {
                ForEach(model.confirmed) { fact in
                    GlassPanel(padding: 14) {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(theme.secondary)
                                .frame(width: 5, height: 5)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(fact.text)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(theme.textPrimary)
                                if let expires = fact.expiresOn {
                                    Text("until \(expires.description)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(theme.textSecondary)
                                }
                            }
                            Spacer()
                            Button {
                                Task { await model.forget(fact) }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9))
                                    .foregroundStyle(theme.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .help("Forget this")
                        }
                    }
                }
            }
        }
    }

    // MARK: Annotations

    private var annotations: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                PanelLabel("Context")
                Spacer()
                Button("Add a period") { model.isAddingAnnotation = true }
                    .buttonStyle(PillButton(tint: theme.primary))
            }

            Text("Mark the weeks that explain your data. A dip during illness is "
               + "illness, not decline — without this she will tell you a confident, "
               + "wrong story about your own life.")
                .font(.system(size: 11.5))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.annotations.isEmpty {
                EmptyMetricState("No periods marked.")
            } else {
                ForEach(model.annotations) { annotation in
                    GlassPanel(padding: 14) {
                        HStack(spacing: 12) {
                            Text(annotation.kind.label)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(theme.primary)
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 6)
                                    .fill(theme.primary.opacity(0.13)))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(annotation.range.start.description) — "
                                   + "\(annotation.range.end.description)")
                                    .font(.system(size: 12)).monospacedDigit()
                                    .foregroundStyle(theme.textPrimary)
                                Text("\(annotation.dayCount) day"
                                   + (annotation.dayCount == 1 ? "" : "s")
                                   + (annotation.note.map { " · \($0)" } ?? ""))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(theme.textSecondary)
                            }
                            Spacer()
                            Button {
                                Task { await model.remove(annotation) }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9))
                                    .foregroundStyle(theme.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $model.isAddingAnnotation) {
            AnnotationEditor(model: model)
        }
    }
}

/// Add a period.
private struct AnnotationEditor: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: MemoryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Mark a period")
                .font(.system(size: 17, weight: .medium, design: .rounded))

            Picker("What happened", selection: $model.draftKind) {
                ForEach(Annotation.Kind.allCases, id: \.self) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.menu)

            DatePicker("From", selection: $model.draftStart, displayedComponents: .date)
            DatePicker("To", selection: $model.draftEnd, displayedComponents: .date)

            TextField("Note (optional)", text: $model.draftNote)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    Task { await model.addAnnotation(); dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                // An end before a start is not a period. Better to disable the
                // button than to store it and silently never match anything.
                .disabled(model.draftEnd < model.draftStart)
            }
        }
        .padding(26)
        .frame(width: 380)
    }
}

private struct PillButton: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(tint.opacity(configuration.isPressed ? 0.6 : 0.3)))
    }
}
