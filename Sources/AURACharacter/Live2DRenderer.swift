import SwiftUI
import AURACore

#if canImport(CubismBridge)
import CubismBridge
import MetalKit
import QuartzCore

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
        // `initWithDirectory:error:` imports as throwing, so the bridge's
        // reason — a missing file, or a Core too old for this rig — reaches the
        // caller instead of collapsing into "unreadable".
        self.model = try CubismModelHandle(directory: directory.path)
    }

    /// True once an `MTKView` is driving frames, so the fallback timer stands
    /// down. Two things calling `tick` would advance physics at twice real
    /// speed — the hair would behave as though gravity had doubled.
    private var isDisplayDriven = false

    public func start() {
        guard ticker == nil, !isDisplayDriven else { return }
        // A timer, not a display link, and deliberately the *fallback*: it runs
        // only until a Metal view attaches. It exists so a renderer that is
        // alive but not on screen still advances, which keeps `apply` honest.
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

    // MARK: - Frames from the view

    /// Called by `Live2DStageView` when it takes over frame timing.
    func displayWillDrive() {
        isDisplayDriven = true
        stop()
    }

    func displayStoppedDriving() {
        isDisplayDriven = false
    }

    /// Advance one frame. The Metal view calls this at display rate.
    func advance(_ deltaTime: TimeInterval) {
        tick(deltaTime)
    }

    func prepareRenderer(device: MTLDevice, drawableSize: CGSize) -> Bool {
        model.prepareRenderer(with: device, drawableSize: drawableSize)
    }

    func drawableSizeChanged(_ size: CGSize) {
        model.setDrawableSize(size)
    }

    func draw(commandBuffer: MTLCommandBuffer,
              renderPassDescriptor: MTLRenderPassDescriptor) {
        model.draw(with: commandBuffer, renderPassDescriptor: renderPassDescriptor)
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
///
/// The view owns frame timing. `MTKView`'s delegate is driven by a
/// `CVDisplayLink`, so frames land in step with the display rather than on a
/// timer that drifts against it — which for a face is the difference between
/// motion and judder.
public struct Live2DStageView: NSViewRepresentable {
    let renderer: Live2DRenderer

    public init(renderer: Live2DRenderer) { self.renderer = renderer }

    public func makeCoordinator() -> Coordinator { Coordinator(renderer: renderer) }

    public func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.delegate = context.coordinator
        // Transparent: she is composited over the themed background, and an
        // opaque black rectangle behind her is exactly the "figure pasted on a
        // dead panel" look the whole stage is built to avoid.
        view.layer?.isOpaque = false
        view.isOpaque = false
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        renderer.displayWillDrive()
        return view
    }

    public func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.renderer = renderer
    }

    public static func dismantleNSView(_ view: MTKView, coordinator: Coordinator) {
        view.delegate = nil
        coordinator.renderer.displayStoppedDriving()
    }

    /// `MTKViewDelegate` is not `@MainActor`-annotated, and `MTKView` calls it
    /// on the main thread anyway. Under Swift 6's strict checking that mismatch
    /// is the most likely thing in this file to need an adjustment on the first
    /// build — probably `nonisolated` methods with a `MainActor.assumeIsolated`
    /// inside. Left as the honest shape until a compiler says otherwise.
    @MainActor
    public final class Coordinator: NSObject, MTKViewDelegate {
        var renderer: Live2DRenderer
        private var prepared = false
        private var lastFrame: CFTimeInterval?

        init(renderer: Live2DRenderer) {
            self.renderer = renderer
        }

        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            renderer.drawableSizeChanged(size)
        }

        public func draw(in view: MTKView) {
            guard let device = view.device,
                  let descriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let queue = Self.queue(for: device),
                  let commandBuffer = queue.makeCommandBuffer()
            else { return }

            // Built on the first frame rather than in makeNSView: the drawable
            // size is not known until the view has been laid out, and the
            // renderer sizes its mask buffers from it.
            if !prepared {
                prepared = renderer.prepareRenderer(
                    device: device, drawableSize: view.drawableSize)
                guard prepared else { return }
            }

            // Measured, not assumed to be 1/60: `preferredFramesPerSecond` is a
            // request, and a dropped frame that advances physics by the wrong
            // amount shows up as a hitch in the hair.
            let now = CACurrentMediaTime()
            let delta = lastFrame.map { min(now - $0, 1.0 / 20.0) } ?? 1.0 / 60.0
            lastFrame = now
            renderer.advance(delta)

            renderer.draw(commandBuffer: commandBuffer,
                          renderPassDescriptor: descriptor)
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        /// One queue per device, for the lifetime of the process. Creating a
        /// command queue per frame is a documented way to stall.
        private static var queues: [ObjectIdentifier: MTLCommandQueue] = [:]
        private static func queue(for device: MTLDevice) -> MTLCommandQueue? {
            let key = ObjectIdentifier(device)
            if let existing = queues[key] { return existing }
            guard let made = device.makeCommandQueue() else { return nil }
            queues[key] = made
            return made
        }
    }
}
#endif

/// Nothing throws these any more.
///
/// `modelUnreadable` was thrown when the bridge returned nil without saying
/// why; the bridge now throws an `NSError` carrying the actual reason, which is
/// strictly better. `missingParameter` was always documentation — a rig missing
/// a parameter is reported by `CharacterManifest.missingParameters()` at
/// install time, which is the point at which it can still be fixed.
///
/// Kept rather than deleted: both name real failure modes, and a caller that
/// wants to classify rather than display needs something to match on.
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
