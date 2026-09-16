import SwiftUI
import AURACore
import AURAStore
import AURAAnalytics
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
            .environment(\.theme, .cyberNeon)
            .preferredColorScheme(.dark)
            .frame(minWidth: 1180, minHeight: 760)
            .task { await container.open() }
        }
        .windowStyle(.hiddenTitleBar)
    }
}

/// Dashboard and conversation, sharing one store and one model.
struct RootView: View {
    @Environment(\.theme) private var theme
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
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .overview:  "square.grid.2x2"
            case .companion: "bubble.left.and.text.bubble.right"
            case .memory:    "brain"
            case .data:      "arrow.down.doc"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(theme.surfaceStroke)

            switch section {
            case .overview:
                DashboardView(model: DashboardViewModel(store: store),
                              onImport: { section = .data })
                    .id(dataVersion)
            case .companion:
                // Rebuilt per appearance rather than held: the conversation is
                // deliberately not persistent yet. Memory is M7, and a
                // transcript that survives navigation but not a relaunch would
                // imply a continuity that does not exist.
                ConversationView(model: ConversationViewModel(
                    model: container.languageModel,
                    briefBuilder: BriefBuilder(store: store, memory: container.memory),
                    voice: container.voice,
                    transcriber: container.transcriber,
                    day: container.latestDay ?? CalendarDay(Date())))

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
                // Rebuilt per appearance like the conversation: an import is a
                // one-shot operation and a screen still showing last week's
                // counts is a screen claiming something happened just now.
                ImportView(
                    model: ImportViewModel(store: store) { range in
                        container.noteImport(range: range)
                    },
                    onDone: {
                        dataVersion += 1
                        section = .overview
                    })
            }
        }
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

/// Owns the store's lifetime.
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

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        return base.appending(path: "AURA")
    }

    /// Records what an import changed.
    ///
    /// `latestDay` seeds the conversation's default day, so leaving it at the
    /// value read when the app launched would have her answering questions
    /// about a day that is no longer the most recent one.
    func noteImport(range: DayRange?) {
        if let range { latestDay = range.end }
    }

    func open() async {
        guard case .opening = status else { return }
        do {
            let store = try SQLiteHealthStore(url: Self.storeURL)
            latestDay = try await store.availableRange()?.end

            // Memory is optional in the strict sense: if it cannot be opened,
            // the dashboard and the health data are unaffected and the app says
            // so on that one screen rather than refusing to start.
            memory = try? MemoryStore(url: Self.memoryURL)

            status = .ready(store)

            // Load the weights now rather than when she is first asked
            // something. The first generation after a cold load pays several
            // seconds for them, and paying that while she is meant to be
            // answering is the difference between a companion and a progress
            // bar. Failure here is not fatal -- the dashboard does not need it.
            Task { [weak self, languageModel] in
                try? await languageModel.warmUp()
                await MainActor.run { self?.isModelReady = languageModel.isReady }
            }

            // Whisper's weights download on first use. Fetching them now means
            // the first thing you say is not also the thing that waits for a
            // download.
            Task { [transcriber] in try? await transcriber.prepare() }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
