import Foundation
import AURACore

/// A local language model.
///
/// Two conformers planned (docs/INTELLIGENCE.md):
///   - `MLXModel`    -- MLX Swift, weights loaded in-process, no daemon.
///                      The default: one app, one process, works offline.
///   - `OllamaModel` -- HTTP to a local Ollama daemon. Easiest way to try a
///                      different model without touching the app.
///
/// There is deliberately no hosted-API conformer in the default build. Four
/// years of a person's health data is the most sensitive thing on this machine
/// and the whole premise of the project is that it never leaves it.
public protocol LanguageModel: AnyObject, Sendable {
    var identifier: String { get }
    var isReady: Bool { get }

    func warmUp() async throws

    /// Streaming completion. Streamed rather than awaited because she is meant
    /// to start speaking while still thinking -- a five-second silent pause
    /// before a wall of text feels like a batch job, not a companion.
    func complete(
        system: String,
        user: String,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String
}

public enum ModelError: Error, Sendable {
    case notLoaded
    case weightsMissing(String)
    case contextOverflow(tokens: Int, limit: Int)
}
