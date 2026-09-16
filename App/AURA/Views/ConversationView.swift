import SwiftUI
import AURACore
import AURADesign
import AURACharacter
import AURAIntelligence
import AURAVoice

/// The companion screen: her on the left, the conversation on the right.
///
/// Matches the published design. The one thing worth noticing in the layout is
/// that she is *large* and permanent rather than an avatar beside a chat log —
/// the conversation is happening with someone, not with a text box.
public struct ConversationView: View {
    @Environment(\.theme) private var theme
    @State private var model: ConversationViewModel
    @FocusState private var inputFocused: Bool

    private let manifest: CharacterManifest
    private let rigDirectory: URL?

    public init(model: ConversationViewModel,
                manifest: CharacterManifest = .placeholder,
                rigDirectory: URL? = nil) {
        _model = State(wrappedValue: model)
        self.manifest = manifest
        self.rigDirectory = rigDirectory
    }

    public var body: some View {
        HStack(spacing: 0) {
            stage
                .frame(width: 520)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(theme.surfaceStroke)
                        .frame(width: 1)
                }

            transcript
        }
        .background(theme.background)
    }

    // MARK: Stage

    private var stage: some View {
        CharacterStageView(state: model.characterState, mood: .calm,
                           manifest: manifest, rigDirectory: rigDirectory)
            .overlay(alignment: .top) {
                HStack {
                    Spacer()
                    if model.isListening {
                        statusChip("Listening", tint: theme.accent)
                    } else if case .speaking = model.characterState {
                        statusChip("Speaking", tint: theme.dataSeries[3])
                    } else if model.status == .thinking {
                        statusChip("Thinking", tint: theme.secondary)
                    }
                }
                .padding(26)
            }
    }

    private func statusChip(_ text: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(tint).frame(width: 6, height: 6)
                .shadow(color: tint, radius: 5)
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(theme.textSecondary)
        }
    }

    // MARK: Transcript

    private var transcript: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.surfaceStroke)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if model.turns.isEmpty { opener }
                        ForEach(model.turns) { turn in
                            TurnBubble(turn: turn).id(turn.id)
                        }
                        if model.withheldCount > 0 { guardNotice }
                    }
                    .padding(30)
                }
                .onChange(of: model.turns.last?.text) { _, _ in
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(model.turns.last?.id, anchor: .bottom)
                    }
                }
            }

            composer
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Conversation")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                Text("Everything on this machine")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            if model.hasTranscript { endButton }
            // Stated plainly, because it is the reason the project exists.
            capsule("No network", tint: theme.dataSeries[3])
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 22)
    }

    /// Ends the conversation, which is also what makes her read it.
    ///
    /// Anything she takes from it is a **proposal** waiting in Memory, not
    /// something she now believes. A companion that quietly accumulates
    /// conclusions about you is unsettling; one that asks is not — and that is
    /// the whole reason nothing here reaches a brief unconfirmed.
    private var endButton: some View {
        Button {
            Task { await model.endConversation() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.bubble").font(.system(size: 10))
                Text("End & remember")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.primary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(theme.primary.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
        .opacity(model.isBusy ? 0.45 : 1)
        .help("Close this conversation so she can read it for anything worth remembering.")
    }

    private func notice(_ text: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(tint)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 30).padding(.vertical, 14)
    }

    private func capsule(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(tint)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().strokeBorder(tint.opacity(0.3)))
    }

    private var opener: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask about any metric, any window, four years back.")
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary)
            // Suggestions rather than an empty box: the useful questions here
            // are not obvious, and a blank prompt invites a wasted first turn.
            ForEach(Self.suggestions, id: \.self) { suggestion in
                Button { model.ask(suggestion) } label: {
                    Text(suggestion)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondary)
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(theme.surfaceStroke))
                }
                .buttonStyle(.plain)
            }
        }
    }

    static let suggestions = [
        "How has my sleep been this year?",
        "Why do I feel tired if I slept well?",
        "Is my activity trending up or down?",
    ]

    /// Shown only when the guard actually fired.
    ///
    /// Not an apology and not hidden. A withheld sentence otherwise reads as her
    /// trailing off mid-thought, and the honest explanation is better than the
    /// mystery.
    private var guardNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 13))
                .foregroundStyle(theme.dataSeries[4])
            Text(model.withheldCount == 1
                 ? "One sentence was held back because it stated a figure that was not computed from your data."
                 : "\(model.withheldCount) sentences were held back because they stated figures that were not computed from your data.")
                .font(.system(size: 11.5))
                .foregroundStyle(theme.textSecondary)
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 11)
            .fill(theme.dataSeries[4].opacity(0.06))
            .strokeBorder(theme.dataSeries[4].opacity(0.2)))
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 0) {
            Divider().overlay(theme.surfaceStroke)

            if let error = model.listeningError {
                notice(error, tint: theme.dataSeries[4])
            }

            if case .unavailable(let reason) = model.status {
                notice(reason, tint: theme.dataSeries[4])
            }

            HStack(spacing: 12) {
                TalkButton(isListening: model.isListening, level: model.inputLevel)
                    // Hold to talk, release to send. A press-and-hold gesture
                    // rather than a toggle, because the key being down IS the
                    // recording — there is no state to get out of sync.
                    .onLongPressGesture(minimumDuration: 0.01, maximumDistance: .infinity) {
                    } onPressingChanged: { pressing in
                        pressing ? model.startTalking() : model.stopTalking()
                    }

                TextField("Ask her something…", text: $model.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .onSubmit { model.send() }

                if model.isBusy {
                    // Interrupting is the primary action while she is talking,
                    // so it takes the send button's place rather than hiding
                    // in a corner.
                    Button(action: model.interrupt) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.accent)
                            .padding(7)
                            .background(Circle().strokeBorder(theme.accent.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                } else {
                    Button(action: model.send) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.background)
                            .padding(7)
                            .background(Circle().fill(theme.primary))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 13).fill(theme.surface)
                .strokeBorder(theme.surfaceStroke))
            .padding(.horizontal, 30)
            .padding(.vertical, 18)
        }
    }
}

/// Hold to talk. Shows what it is hearing while held.
private struct TalkButton: View {
    @Environment(\.theme) private var theme
    let isListening: Bool
    let level: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(isListening ? theme.accent.opacity(0.18) : Color.clear)
                .strokeBorder(isListening ? theme.accent : theme.surfaceStroke)
                .frame(width: 32, height: 32)

            // The ring grows with what the microphone hears. Without it a held
            // key is indistinguishable from a dead microphone until you let go
            // and nothing happens.
            if isListening {
                Circle()
                    .strokeBorder(theme.accent.opacity(0.4), lineWidth: 2)
                    .frame(width: 32 + level * 16, height: 32 + level * 16)
                    .animation(.linear(duration: 0.08), value: level)
            }

            Image(systemName: "mic")
                .font(.system(size: 12))
                .foregroundStyle(isListening ? theme.accent : theme.textSecondary)
        }
        .frame(width: 50, height: 50)
        .contentShape(Circle())
        .help("Hold to talk")
    }
}

/// One turn in the transcript.
private struct TurnBubble: View {
    @Environment(\.theme) private var theme
    let turn: ConversationViewModel.Turn

    var body: some View {
        HStack {
            if turn.speaker == .you { Spacer(minLength: 60) }

            VStack(alignment: .leading, spacing: 11) {
                Text(turn.text)
                    .font(.system(size: 13.5))
                    .lineSpacing(3)
                    .foregroundStyle(turn.speaker == .you
                                     ? theme.textPrimary : theme.textPrimary.opacity(0.85))
                    .textSelection(.enabled)

                if turn.isStreaming && turn.text.isEmpty {
                    ThinkingDots()
                }

                if !turn.citations.isEmpty {
                    // Every figure traceable to a computed value. The point is
                    // not decoration: it is that she cannot state one that is
                    // not here.
                    FlowRow(spacing: 6) {
                        ForEach(turn.citations) { citation in
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                Text(citation.matched)
                                    .font(.system(size: 10, weight: .medium))
                                    .monospacedDigit()
                                Text(citation.label)
                                    .font(.system(size: 10))
                                    .foregroundStyle(theme.textSecondary)
                            }
                            .foregroundStyle(theme.secondary)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(theme.secondary.opacity(0.09))
                                .strokeBorder(theme.secondary.opacity(0.22)))
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(turn.speaker == .you
                          ? theme.primary.opacity(0.13) : theme.surface)
                    .strokeBorder(theme.surfaceStroke)
            }
            .frame(maxWidth: turn.speaker == .you ? 420 : 520, alignment: .leading)

            if turn.speaker == .aura { Spacer(minLength: 40) }
        }
    }
}

/// The pause before her first sentence — the only moment she is silent, since
/// after that she speaks as she generates.
private struct ThinkingDots: View {
    @Environment(\.theme) private var theme
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(theme.textSecondary)
                    .frame(width: 5, height: 5)
                    .opacity(0.3 + 0.7 * abs(sin(phase + Double(i) * 0.6)))
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                phase += 0.25
            }
        }
    }
}

/// Wraps its children onto as many lines as they need.
private struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
