import SwiftUI
import AURACore
import AURAStore
import AURAAnalytics
import AURACharacter
import AURADesign
import AURAIntelligence
import AURAVoice
import AURAMemory

/// The app shell. Deliberately thin — views and wiring only.
///
/// Anything with logic worth testing lives in a package under `Sources/`, so it
/// can be built and tested from the command line and, later, linked by an iOS
/// companion without moving.
@main
struct AURAApp: App {

    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            Group {
                switch container.status {
                case .opening:
                    ProgressView().controlSize(.large)

                case .ready(let store):
                    RootView(store: store, container: container)

                case .failed(let message):
                    // A store that will not open is not something to paper over
                    // with an empty dashboard — four years of health data either
                    // loaded or it did not.
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 28))
                        Text("Could not open your health store")
                            .font(.headline)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Text(AppContainer.storeURL.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                    .padding(40)
                }
            }
            .environment(\.theme, container.preferences.theme)
            .preferredColorScheme(container.preferences.theme.isLight ? .light : .dark)
            .frame(minWidth: 1180, minHeight: 760)
            .task { await container.open() }
        }
        .windowStyle(.hiddenTitleBar)
    }
}

/// Dashboard, conversation, memory, import and settings, sharing one store and
/// one model.
struct RootView: View {
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    let store: SQLiteHealthStore
    let container: AppContainer

    @State private var section: Section = .overview

    /// Bumped by a finished import so the dashboard rebuilds against the data
    /// that now exists, rather than keeping the figures it loaded from the
    /// store as it was before.
    @State private var dataVersion = 0

    enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case companion = "Companion"
        case memory = "Memory"
        case data = "Import"
        case settings = "Settings"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .overview:  "square.grid.2x2"
            case .companion: "bubble.left.and.text.bubble.right"
            case .memory:    "brain"
            case .data:      "arrow.down.doc"
            case .settings:  "slider.horizontal.3"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(theme.surfaceStroke)

            ZStack(alignment: .top) {
                content
                if let brief = container.morningBrief { morningBriefBanner(brief) }
            }
        }
        // Preferences that change something already running, rather than
        // something read on the next redraw.
        .onChange(of: container.preferences.morningBriefEnabled) { _, _ in
            container.refreshMorningBrief()
        }
        .onChange(of: container.preferences.morningBriefHour) { _, _ in
            container.refreshMorningBrief()
        }
        // Hiding the app is the closest thing macOS gives to "done for now".
        // Reading the conversation for things worth remembering there means a
        // session that is never explicitly ended still gets read once.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            Task { await container.closeConversation() }
        }
        // Confirming or rejecting a proposal happens inside `MemoryView`, which
        // owns its own view model. Re-counting on navigation is enough to keep
        // the badge honest without wiring a callback through it.
        .onChange(of: section) { _, _ in
            Task { await container.refreshProposedFacts() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .overview:
            DashboardView(model: DashboardViewModel(store: store,
                                                    goals: container.preferences.goals),
                          onImport: { section = .data },
                          characterManifest: container.characterManifest,
                          rigDirectory: AppContainer.characterURL)
                // Rebuilt when an import lands, and when the goals change: goal
                // progress is read once at load, so a new target would
                // otherwise sit against the old one until a relaunch.
                .id("\(dataVersion)-\(container.preferences.goals.hashValue)")

        case .companion:
            // Held by the container rather than rebuilt per appearance: the
            // transcript is now recorded to memory, and a view model recreated
            // on every navigation would split one conversation into several.
            ConversationView(model: container.conversation(for: store),
                             manifest: container.characterManifest,
                             rigDirectory: AppContainer.characterURL)

        case .memory:
            if let memory = container.memory {
                MemoryView(model: MemoryViewModel(memory: memory))
            } else {
                // Memory failing to open must not take the dashboard with
                // it — the health data is intact either way.
                VStack(spacing: 8) {
                    Image(systemName: "brain").font(.system(size: 26))
                    Text("Memory is unavailable")
                        .font(.system(size: 13))
                }
                .foregroundStyle(theme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

        case .data:
            // Rebuilt per appearance: an import is a one-shot operation and a
            // screen still showing last week's counts is a screen claiming
            // something happened just now.
            ImportView(
                model: ImportViewModel(store: store) { range in
                    container.noteImport(range: range)
                },
                onDone: {
                    dataVersion += 1
                    section = .overview
                })

        case .settings:
            SettingsView(
                model: SettingsViewModel(store: store,
                                         memory: container.memory,
                                         preferences: container.preferences),
                preferences: container.preferences,
                status: container.componentStatus())
        }
    }

    /// The one time she speaks first, and therefore the one thing allowed to
    /// appear over whatever you were looking at.
    ///
    /// Dismissible, and dismissed for the day — `MorningBriefScheduler` marks
    /// the day done whether or not there was anything to say, so it cannot
    /// reappear at 08:15 and again at 08:30.
    private func morningBriefBanner(_ brief: MorningBrief.Outcome) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "sun.horizon")
                .font(.system(size: 14))
                .foregroundStyle(theme.primary)
            VStack(alignment: .leading, spacing: 4) {
                Text(brief.text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Ask her about it") {
                    container.dismissMorningBrief()
                    section = .companion
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.primary)
            }
            Spacer(minLength: 0)
            Button { container.dismissMorningBrief() } label: {
                Image(systemName: "xmark").font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.textSecondary)
        }
        .padding(15)
        .frame(maxWidth: 680)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(theme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(theme.primary.opacity(0.4), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
        }
        .padding(.top, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(theme.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AURA")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .tracking(1)
                    Text("HEALTH COMPANION")
                        .font(.system(size: 7.5, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 26)

            ForEach(Section.allCases) { item in
                Button { section = item } label: {
                    HStack(spacing: 11) {
                        Image(systemName: item.icon)
                            .font(.system(size: 13))
                            .frame(width: 18)
                        Text(item.rawValue)
                            .font(.system(size: 12,
                                          weight: section == item ? .semibold : .regular))
                        Spacer()
                        if item == .memory, container.proposedFactCount > 0 {
                            // A proposal is a question waiting for an answer.
                            // Unanswered, it does nothing at all — nothing
                            // reaches a brief until it is confirmed — so it has
                            // to be visible from anywhere in the app.
                            Text("\(container.proposedFactCount)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(theme.background)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(theme.primary))
                        }
                    }
                    .foregroundStyle(section == item ? theme.textPrimary : theme.textSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 9)
                        .fill(section == item ? theme.primary.opacity(0.13) : .clear))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                Text("LOCAL · OFFLINE")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(theme.textSecondary.opacity(0.7))
                HStack(spacing: 7) {
                    Circle()
                        .fill(container.isModelReady ? theme.dataSeries[3] : theme.textSecondary)
                        .frame(width: 6, height: 6)
                    Text(container.isModelReady
                         ? container.languageModel.identifier
                         : "loading model…")
                        .font(.system(size: 9.5))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 18)
        }
        .padding(.top, 26)
        .frame(width: 196)
        .background(theme.background)
    }
}

/// Owns the store's lifetime, and everything else with a lifetime.
@Observable
@MainActor
final class AppContainer {

    enum Status {
        case opening
        case ready(SQLiteHealthStore)
        case failed(String)
    }

    private(set) var status: Status = .opening
    private(set) var latestDay: CalendarDay?

    @ObservationIgnored let preferences = Preferences()

    /// One voice and one model for the app's lifetime.
    ///
    /// Not per-screen: the weights are gigabytes and loading them twice would
    /// exhaust the memory budget that `docs/INTELLIGENCE.md` sizes to the byte.
    ///
    /// `@ObservationIgnored` because they are dependencies, not UI state — and
    /// because `lazy` does not survive the `@Observable` macro's rewrite of
    /// stored properties.
    @ObservationIgnored let voice: any VoiceEngine =
        VoiceFactory.speech(modelDirectory: AppContainer.folder.appending(path: "voice"))
    @ObservationIgnored let transcriber: any TranscriptionEngine = VoiceFactory.transcription()
    @ObservationIgnored let languageModel: any LanguageModel = ModelFactory.local()

    /// Its own file, next to the health store. See `MemoryStore` for why the
    /// two are separate.
    @ObservationIgnored private(set) var memory: MemoryStore?
    @ObservationIgnored private(set) var keeper: MemoryKeeper?
    @ObservationIgnored private var conversationModel: ConversationViewModel?
    @ObservationIgnored private var scheduler: MorningBriefScheduler?

    /// Which renderer the character screen should use, and where its assets
    /// are. `.placeholder` until a rig is installed, which is most of this
    /// project's life.
    private(set) var characterManifest: CharacterManifest = .placeholder

    /// Set when she has something worth saying unprompted. Nil the rest of the
    /// time, which is nearly always.
    private(set) var morningBrief: MorningBrief.Outcome?

    /// Facts waiting for a yes or no. Shown as a badge, because an unconfirmed
    /// inference does nothing until it is answered.
    private(set) var proposedFactCount = 0

    /// Mirrors the model's readiness as observable state.
    ///
    /// `languageModel.isReady` is ignored by observation, so reading it in a
    /// view body would render once and never update when the weights finish
    /// loading — the status dot would sit grey forever.
    private(set) var isModelReady = false

    /// One folder, under Application Support. Everything AURA knows lives here
    /// and nowhere else, so backing it up or deleting it is a single decision.
    static var storeURL: URL { folder.appending(path: "aura.sqlite") }
    static var memoryURL: URL { folder.appending(path: "memory.sqlite") }
    static var characterURL: URL { folder.appending(path: "character") }
    /// Where a restored backup waits until the next launch. See
    /// `applyPendingRestore`.
    static var stagingURL: URL { folder.appending(path: "restore-pending") }

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        return base.appending(path: "AURA")
    }

    func open() async {
        guard case .opening = status else { return }

        // Before anything opens a database. A restore that overwrote a live
        // SQLite file would corrupt it, and quietly.
        Self.applyPendingRestore()

        do {
            let store = try SQLiteHealthStore(url: Self.storeURL)
            latestDay = try await store.availableRange()?.end

            // Memory is optional in the strict sense: if it cannot be opened,
            // the dashboard and the health data are unaffected and the app says
            // so on that one screen rather than refusing to start.
            memory = try? MemoryStore(url: Self.memoryURL)
            if let memory {
                keeper = MemoryKeeper(model: languageModel, memory: memory)
            }

            characterManifest = CharacterManifest.load(from: Self.characterURL)

            status = .ready(store)
            await refreshProposedFacts()

            // Load the weights now rather than when she is first asked
            // something. The first generation after a cold load pays several
            // seconds for them, and paying that while she is meant to be
            // answering is the difference between a companion and a progress
            // bar. Failure here is not fatal -- the dashboard does not need it.
            Task { [weak self, languageModel] in
                try? await languageModel.warmUp()
                guard let self else { return }
                self.isModelReady = languageModel.isReady
                guard languageModel.isReady else { return }

                // Both need the model, so both wait for it. Summarising first:
                // it is bounded work that keeps context from growing without
                // limit, and it must not compete with a generation she is
                // about to be asked for.
                await self.keeper?.summariseOldConversations()
                self.startMorningBrief(store: store)
            }

            // Whisper's weights download on first use. Fetching them now means
            // the first thing you say is not also the thing that waits for a
            // download.
            Task { [transcriber] in try? await transcriber.prepare() }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: Conversation

    /// One conversation per app run, not per visit to the screen.
    ///
    /// The transcript is written to memory now, so rebuilding this on every
    /// navigation would record one conversation as four and give
    /// `MemoryKeeper` four fragments to summarise instead of one exchange.
    func conversation(for store: SQLiteHealthStore) -> ConversationViewModel {
        if let existing = conversationModel { return existing }
        let model = ConversationViewModel(
            model: languageModel,
            briefBuilder: BriefBuilder(store: store,
                                       goals: preferences.goals,
                                       memory: memory),
            voice: voice,
            transcriber: transcriber,
            day: latestDay ?? CalendarDay(Date()),
            memory: memory,
            keeper: keeper)
        conversationModel = model
        return model
    }

    /// End the current conversation and read it for things worth remembering.
    func closeConversation() async {
        guard let conversationModel, conversationModel.hasTranscript else { return }
        await conversationModel.endConversation()
        await refreshProposedFacts()
    }

    func refreshProposedFacts() async {
        proposedFactCount = (try? await memory?.facts(status: .proposed).count) ?? 0
    }

    // MARK: Morning brief

    private func startMorningBrief(store: SQLiteHealthStore) {
        scheduler?.stop()
        scheduler = nil
        guard preferences.morningBriefEnabled else { return }

        let brief = MorningBrief(
            store: store,
            briefBuilder: BriefBuilder(store: store, goals: preferences.goals, memory: memory),
            model: languageModel)

        let scheduler = MorningBriefScheduler { [weak self] outcome in
            self?.morningBrief = outcome
        }
        scheduler.hour = preferences.morningBriefHour
        scheduler.start {
            // Composed against the most recent day with data, not today: at
            // 08:00 today has barely started, and a brief about four hours of
            // an unfinished day is not a brief about anything.
            guard let day = try? await store.availableRange()?.end else { return nil }
            return try? await brief.compose(for: day)
        }
        self.scheduler = scheduler
    }

    /// Restart the scheduler after its preferences change. Without this, turning
    /// the brief off leaves the running timer in place.
    func refreshMorningBrief() {
        guard case .ready(let store) = status, isModelReady else { return }
        startMorningBrief(store: store)
        if !preferences.morningBriefEnabled { morningBrief = nil }
    }

    func dismissMorningBrief() { morningBrief = nil }

    // MARK: Import and restore

    /// Records what an import changed.
    ///
    /// `latestDay` seeds the conversation's default day, so leaving it at the
    /// value read when the app launched would have her answering questions
    /// about a day that is no longer the most recent one.
    func noteImport(range: DayRange?) {
        if let range { latestDay = range.end }
        // The conversation is rebuilt so its next brief is about the new data.
        conversationModel = nil
    }

    /// Move a staged restore into place, if there is one.
    ///
    /// Called before any database is opened. The `-wal` and `-shm` sidecars of
    /// the *old* database are deleted along with it: leaving them would let
    /// SQLite replay the previous write-ahead log over the restored file, which
    /// is a corrupt database that opens without complaint.
    private static func applyPendingRestore() {
        let fm = FileManager.default
        let staging = stagingURL
        guard let staged = try? fm.contentsOfDirectory(at: staging,
                                                       includingPropertiesForKeys: nil),
              !staged.isEmpty else { return }

        for file in staged {
            let destination = folder.appending(path: file.lastPathComponent)
            for suffix in ["", "-wal", "-shm"] {
                try? fm.removeItem(at: destination.appendingSuffix(suffix))
            }
            try? fm.moveItem(at: file, to: destination)
        }
        try? fm.removeItem(at: staging)
    }

    // MARK: Status

    /// What is actually working, for the Settings screen. Deliberately reports
    /// the honest "not here yet" states rather than what is configured.
    func componentStatus() -> [SettingsView.StatusLine] {
        var lines: [SettingsView.StatusLine] = [
            .init(label: "Language model",
                  detail: isModelReady
                      ? languageModel.identifier
                      : ((languageModel as? UnavailableModel)?.reason ?? "loading…"),
                  isReady: isModelReady),
            .init(label: "Voice", detail: voice.identifier, isReady: true),
            .init(label: "Memory",
                  detail: memory == nil
                      ? "could not open \(Self.memoryURL.lastPathComponent)"
                      : "\(proposedFactCount) proposal\(proposedFactCount == 1 ? "" : "s") waiting",
                  isReady: memory != nil),
        ]

        let missing = characterManifest.missingParameters()
        switch characterManifest.renderer {
        case .procedural:
            lines.append(.init(label: "Character",
                               detail: "procedural placeholder — no rig installed",
                               isReady: false))
        case .live2d:
            lines.append(.init(
                label: "Character",
                detail: missing.isEmpty
                    ? "Live2D rig at \(characterManifest.assetPath)"
                    : "rig is missing \(missing.joined(separator: ", "))",
                isReady: missing.isEmpty))
        }
        return lines
    }
}
