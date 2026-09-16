import SwiftUI
import AURACore

#if canImport(CubismBridge)
import CubismBridge
import MetalKit

/// The rig, once it exists.
///
/// ## Read this before trusting any of it
///
/// **This is the least verified code in the project, by a distance.** Everything
/// else was either run (the Python) or written against an API read from its own
/// source (MLX, WhisperKit, Kokoro). The Cubism SDK is a proprietary C++
/// download that is not in this repository and could not be compiled against
/// here, so the bridge below is written from the published API shape and the
/// exact call signatures need checking on first build.
///
/// What *is* solid is the seam. The dashboard talks to `CharacterRenderer` and
/// nothing else; the mouth is driven by `MouthShaper`, which was measured; and
/// the parameter mapping is a short table anyone can check against the model in
/// Cubism Editor. If a signature below is wrong, one file changes.
///
/// ## What it drives
///
/// | from | Cubism parameter |
/// |---|---|
/// | `look(at:)` | `ParamAngleX/Y`, `ParamEyeBallX/Y` |
/// | `speaking(level:)` → `MouthShaper` | `ParamMouthOpenY` |
/// | blink timer | `ParamEyeLOpen`, `ParamEyeROpen` |
/// | breathing | `ParamBreath` |
/// | mood | `ParamMouthForm`, `ParamBrowLY/RY`, `ParamBodyAngleZ` |
///
/// Hair and ponytail are not in that table on purpose: they are **physics**,
/// configured in `.physics3.json` and driven by the body parameters above. The
/// renderer does not animate hair, it moves the head and the rig responds.
@Observable
@MainActor
public final class Live2DRenderer: CharacterRenderer {

    public var onTransitionComplete: (@Sendable (CharacterState) -> Void)?

    private let model: CubismModelHandle
    private var mouth = MouthShaper()
    private var clock: TimeInterval = 0
    private var nextBlink: TimeInterval = 4
    private var blinkStarted: TimeInterval?
    private var gaze: CGPoint = .zero
    private var mood: CharacterMood = .neutral
    private var ticker: Task<Void, Never>?

    /// - Parameter directory: holds `.model3.json`, `.moc3`, `.physics3.json`
    ///   and the texture atlas, exactly as the artist delivered them.
    public init(directory: URL) throws {
        guard let handle = CubismModelHandle(directory: directory.path) else {
            throw CharacterError.modelUnreadable(directory)
        }
        self.model = handle
    }

    public func start() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                await self?.tick(1.0 / 60.0)
            }
        }
    }

    public func stop() {
        ticker?.cancel()
        ticker = nil
    }

    // MARK: - CharacterRenderer

    public func apply(state: CharacterState, mood: CharacterMood) {
        self.mood = mood

        if case .speaking(let level) = state {
            model.setParameter("ParamMouthOpenY", value: Float(mouth.next(level)))
        } else {
            mouth.reset()
            model.setParameter("ParamMouthOpenY", value: 0)
        }

        // Mood is expression, not pose. Three parameters carry it, which is why
        // one rig covers every mood rather than needing a drawing each.
        let (form, brow, lean) = Self.expression(for: mood)
        model.setParameter("ParamMouthForm", value: form)
        model.setParameter("ParamBrowLY", value: brow)
        model.setParameter("ParamBrowRY", value: brow)
        model.setParameter("ParamBodyAngleZ", value: lean)

        onTransitionComplete?(state)
    }

    public func look(at point: CGPoint?) {
        gaze = point ?? .zero
    }

    // MARK: - Frame

    private func tick(_ dt: TimeInterval) {
        clock += dt

        // Eyes lead, head follows and less far. A head that tracks as far as
        // the eyes reads as a doll being turned rather than someone looking.
        model.setParameter("ParamEyeBallX", value: Float(gaze.x))
        model.setParameter("ParamEyeBallY", value: Float(-gaze.y))
        model.setParameter("ParamAngleX", value: Float(gaze.x * 18))
        model.setParameter("ParamAngleY", value: Float(-gaze.y * 12))

        model.setParameter("ParamBreath",
                           value: Float((sin(clock * 2 * .pi / 5.0) + 1) / 2))

        if let started = blinkStarted {
            let t = (clock - started) / 0.12
            if t >= 1 {
                blinkStarted = nil
                model.setParameter("ParamEyeLOpen", value: 1)
                model.setParameter("ParamEyeROpen", value: 1)
                nextBlink = clock + Double.random(in: 3...7)
            } else {
                let open = Float(abs(t - 0.5) * 2)
                model.setParameter("ParamEyeLOpen", value: open)
                model.setParameter("ParamEyeROpen", value: open)
            }
        } else if clock >= nextBlink {
            blinkStarted = clock
        }

        // Physics last: it reads the parameters set above and produces the hair.
        model.updatePhysics(Float(dt))
        model.update()
    }

    static func expression(for mood: CharacterMood) -> (Float, Float, Float) {
        switch mood {
        case .motivated: (0.6, 0.3, -2)
        case .calm:      (0.3, 0.0, 0)
        case .concerned: (-0.3, -0.5, 2)
        case .sleepy:    (0.0, -0.3, 3)
        case .proud:     (0.9, 0.5, -3)
        case .neutral:   (0.2, 0.0, 0)
        }
    }
}

/// Hosts the Metal view the model renders into.
public struct Live2DStageView: NSViewRepresentable {
    let renderer: Live2DRenderer

    public init(renderer: Live2DRenderer) { self.renderer = renderer }

    public func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.layer?.isOpaque = false
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        return view
    }

    public func updateNSView(_ view: MTKView, context: Context) {}
}
#endif

public enum CharacterError: Error, Sendable, LocalizedError {
    case modelUnreadable(URL)
    /// The rig is missing a parameter the renderer drives.
    ///
    /// Worth surfacing by name rather than silently doing nothing: a rig
    /// delivered without a usable `ParamMouthOpenY` is the single most likely
    /// thing to be wrong with a commission, and the one hardest to notice.
    case missingParameter(String)

    public var errorDescription: String? {
        switch self {
        case .modelUnreadable(let url):
            "no readable Cubism model in \(url.lastPathComponent)"
        case .missingParameter(let name):
            "the rig has no \(name) parameter"
        }
    }
}
