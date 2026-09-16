import Foundation

/// Which renderer to use, and where its assets are.
///
/// The whole reason `CharacterRenderer` is a protocol. Swapping the procedural
/// placeholder for a rig is a change to this file plus a folder of assets —
/// no dashboard code moves, which was the acceptance criterion for M9 from the
/// start.
public struct CharacterManifest: Codable, Sendable {

    public enum Renderer: String, Codable, Sendable {
        /// One illustration, driven by breathing, sway, blink and parallax.
        case procedural
        /// A rigged Cubism model.
        case live2d
    }

    public var renderer: Renderer
    /// Relative to the character directory.
    public var assetPath: String
    /// Rig parameters this model actually has, when it is a Live2D one.
    ///
    /// Recorded at install rather than discovered at render time, so a rig
    /// missing `ParamMouthOpenY` is caught when you add it — not the first time
    /// she tries to speak.
    public var parameters: [String]?

    public init(renderer: Renderer, assetPath: String, parameters: [String]? = nil) {
        self.renderer = renderer
        self.assetPath = assetPath
        self.parameters = parameters
    }

    public static let placeholder = CharacterManifest(
        renderer: .procedural, assetPath: "procedural")

    /// Parameters the renderer drives. A rig without these cannot be used as is.
    public static let required = [
        "ParamAngleX", "ParamAngleY", "ParamEyeBallX", "ParamEyeBallY",
        "ParamEyeLOpen", "ParamEyeROpen", "ParamMouthOpenY", "ParamMouthForm",
        "ParamBrowLY", "ParamBrowRY", "ParamBodyAngleZ", "ParamBreath",
    ]

    /// What is missing, so a commission can be checked on delivery rather than
    /// on the day she first tries to talk.
    public func missingParameters() -> [String] {
        guard renderer == .live2d, let parameters else { return [] }
        return Self.required.filter { !parameters.contains($0) }
    }

    public static func load(from directory: URL) -> CharacterManifest {
        let url = directory.appending(path: "manifest.json")
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(CharacterManifest.self, from: data)
        else {
            // No manifest means no rig yet, which is the normal state for most
            // of this project's life.
            return .placeholder
        }
        return manifest
    }
}
