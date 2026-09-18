import Foundation
import AURACore

#if canImport(MLXLLM)
import MLXLLM
import MLXLMCommon

/// The narrator, running in-process on the Neural Engine.
///
/// One app, one process, no daemon, no network. Weights are loaded once and
/// stay resident, which is why `warmUp()` exists: the first generation after a
/// cold load pays several seconds for the weights, and paying that while she is
/// meant to be answering you is the difference between a companion and a
/// progress bar.
///
/// ## Sizing
///
/// Default is a 4-bit 14B (`docs/INTELLIGENCE.md`). On the target machine —
/// M5, 24 GB — that is ~8–9 GB of weights against the ~16–18 GB macOS actually
/// hands the GPU, leaving room for the TTS model, Whisper and the app, all of
/// which are resident at the same time during a spoken exchange. A 27B at 4-bit
/// is ~18 GB of weights alone and would swap; the failure mode is not "slower"
/// but her pausing mid-sentence.
///
/// ## Context
///
/// Capped deliberately low. The whole point of `HealthBrief` is that the
/// arithmetic already happened, so a brief is a few hundred tokens rather than
/// the 40 million a raw four-year history would be. Nothing here needs a large
/// window, and every token in the prompt is latency before she speaks.
public final class MLXModel: LanguageModel, @unchecked Sendable {

    public let identifier: String
    public private(set) var isReady = false

    private let maxTokens: Int
    private let loader = ModelLoader()

    /// - Parameters:
    ///   - identifier: a Hugging Face repo id, e.g. `mlx-community/Qwen3-14B-4bit`.
    ///   - maxTokens: generation cap. Long enough for a considered answer, short
    ///     enough that a runaway generation cannot hold the conversation open.
    public init(identifier: String = "mlx-community/Qwen3-14B-4bit",
                maxTokens: Int = 600) {
        self.identifier = identifier
        self.maxTokens = maxTokens
    }

    public func warmUp() async throws {
        _ = try await loadedContainer()
    }

    public func complete(
        system: String,
        user: String,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let container = try await loadedContainer()

        let input = UserInput(chat: [
            .system(system),
            .user(user),
        ])
        let prepared = try await container.prepare(input: input)

        let stream = try await container.generate(
            input: prepared,
            parameters: GenerateParameters(maxTokens: maxTokens))

        var full = ""
        for await event in stream {
            // Cancellation has to be honoured inside the loop: she must stop
            // the moment you interrupt, and an abandoned generation still
            // occupies the GPU the next answer needs.
            try Task.checkCancellation()
            if case .chunk(let text) = event {
                full += text
                onToken(text)
            }
        }
        return full
    }

    // MARK: - Loading

    private func loadedContainer() async throws -> ModelContainer {
        do {
            let loaded = try await loader.container(identifier: identifier)
            // Written redundantly by every caller whose await resolves
            // against the same already-finished load, always to the same
            // value. Technically still a race on this one Bool by the
            // language's formal memory model; not worth an actor hop or a
            // lock to close, since `isReady` has to stay a plain, instantly
            // readable property for the UI's status dot (`LanguageModel`
            // requires `var isReady: Bool { get }`, not `async`) and the
            // actual hazard -- a lock held across the multi-second weight
            // load below -- is what actually mattered and is gone.
            isReady = true
            return loaded
        } catch {
            // A missing model is a setup problem with an obvious fix, and
            // saying so beats a generic failure the user cannot act on.
            throw ModelError.weightsMissing(
                "\(identifier): \(error.localizedDescription)")
        }
    }
}

/// Loads the model weights at most once, however many callers ask before the
/// first load finishes.
///
/// An actor, not a lock. The previous version held an `NSLock` across
/// `await LLMModelFactory.shared.loadContainer(...)` -- a load that can take
/// tens of seconds for several gigabytes of weights. That is a real deadlock
/// and priority-inversion risk on its own, not merely the compile error
/// Swift 6 happens to catch first (`.lock()`/`.unlock()` are unavailable from
/// an async context precisely because holding an OS lock across a suspension
/// point is unsafe). An actor serialises callers by suspending them at the
/// `await`, never by blocking a thread underneath a held lock, which is what
/// "load once, and let concurrent callers join the same in-flight load"
/// actually needs. `Task.value` is itself safe to await from multiple
/// callers, so once the task exists there is nothing left to guard.
private actor ModelLoader {
    private var inFlight: Task<ModelContainer, Error>?

    func container(identifier: String) async throws -> ModelContainer {
        if let inFlight { return try await inFlight.value }
        let started = Task {
            try await LLMModelFactory.shared.loadContainer(
                configuration: ModelConfiguration(id: identifier))
        }
        inFlight = started
        return try await started.value
    }
}
#endif

/// Used when MLX is unavailable or no weights are installed.
///
/// Not a mock and not a fallback that pretends to think — it refuses, with a
/// reason. The dashboard is fully usable without a language model, and the app
/// says the companion is unavailable rather than inventing something to say.
public final class UnavailableModel: LanguageModel, @unchecked Sendable {
    public let identifier = "none"
    public var isReady: Bool { false }
    public let reason: String

    public init(reason: String = "No local model is installed.") {
        self.reason = reason
    }

    public func warmUp() async throws { throw ModelError.notLoaded }

    public func complete(system: String, user: String,
                         onToken: @escaping @Sendable (String) -> Void) async throws -> String {
        throw ModelError.notLoaded
    }
}
