import Foundation
import AURACore

/// A local language model, used for prose.
///
/// Note the narrow job. AURA runs two models and this protocol covers only one
/// of them (docs/INTELLIGENCE.md):
///
///   - **The narrator** -- this protocol. A Qwen3.x-class model via MLX, sized
///     to the machine's unified memory. Writes the words.
///   - **The extractor** -- Apple's Foundation Models framework, used directly
///     rather than through this protocol, because its whole value is the
///     `@Generable` macro and constrained decoding. Anything structured goes
///     there and comes back as a typed Swift value or an error, never as text
///     to be parsed.
///
/// Conformers planned here:
///   - `MLXModel`    -- weights loaded in-process, no daemon. The default.
///   - `OllamaModel` -- HTTP to a local Ollama daemon, for trying a different
///                      model without touching the app.
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
