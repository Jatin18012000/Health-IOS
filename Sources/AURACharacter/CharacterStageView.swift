import SwiftUI
import AURACore
import AURADesign

/// The stage she stands on.
///
/// Composites the character layers and applies the renderer's driven values.
/// Deliberately knows nothing about health data — it is handed a state and a
/// mood and draws them.
public struct CharacterStageView: View {
    @Environment(\.theme) private var theme
    @State private var renderer = ProceduralRenderer()
    @State private var hoverPoint: CGPoint?

    private let assets: CharacterAssets
    private let state: CharacterState
    private let mood: CharacterMood
    private let manifest: CharacterManifest
    /// Where the `.moc3`, `.physics3.json` and textures live. Nil until there
    /// is a rig, which is most of this project's life.
    private let rigDirectory: URL?

    /// Built once, and only when a rig is both configured and loadable. Held as
    /// state so the Metal view is not torn down and rebuilt on every redraw.
    @State private var rig: RigLoad = .notAttempted

    enum RigLoad {
        case notAttempted
        case failed(String)
        #if canImport(CubismBridge)
        case loaded(Live2DRenderer)
        #endif
    }

    public init(state: CharacterState = .idle,
                mood: CharacterMood = .neutral,
                assets: CharacterAssets = .placeholder,
                manifest: CharacterManifest = .placeholder,
                rigDirectory: URL? = nil) {
        self.state = state
        self.mood = mood
        self.assets = assets
        self.manifest = manifest
        self.rigDirectory = rigDirectory
    }

    /// What this build can actually draw, as opposed to what the manifest asks
    /// for.
    ///
    /// The Cubism SDK is a proprietary download that is not in this repository,
    /// so a build without `CubismBridge` linked cannot render a rig no matter
    /// what the manifest says. Falling back silently would make a missing SDK
    /// look like a broken rig; this names it.
    enum Resolution {
        case procedural
        case rig
        case rigUnavailable(String)
    }

    var resolution: Resolution {
        guard manifest.renderer == .live2d else { return .procedural }
        let missing = manifest.missingParameters()
        guard missing.isEmpty else {
            return .rigUnavailable(
                "the rig is missing \(missing.count == 1 ? "parameter" : "parameters") "
                + missing.joined(separator: ", "))
        }
        guard rigDirectory != nil else {
            return .rigUnavailable("no rig folder is configured")
        }
        #if canImport(CubismBridge)
        if case .failed(let reason) = rig { return .rigUnavailable(reason) }
        return .rig
        #else
        return .rigUnavailable("this build has no Cubism SDK linked")
        #endif
    }

    /// Loads the rig, once.
    ///
    /// A failure here degrades to the placeholder with the reason attached
    /// rather than to an empty stage: the character is the least critical thing
    /// on the dashboard and must never be the reason it does not draw.
    private func loadRigIfNeeded() {
        #if canImport(CubismBridge)
        guard manifest.renderer == .live2d,
              case .notAttempted = rig,
              let directory = rigDirectory else { return }
        do {
            // Named apart from `renderer`, the procedural placeholder, which
            // stays alive either way: one of the two draws, both conform to
            // `CharacterRenderer`, and nothing outside this file knows which.
            let live2d = try Live2DRenderer(
                directory: directory.appending(path: manifest.assetPath))
            live2d.start()
            live2d.apply(state: state, mood: mood)
            rig = .loaded(live2d)
        } catch {
            rig = .failed((error as? LocalizedError)?.errorDescription
                          ?? "the rig could not be opened")
        }
        #endif
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(
                        colors: [theme.primary.opacity(0.12), theme.background.opacity(0.6)],
                        startPoint: .top, endPoint: .bottom))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(theme.surfaceStroke, lineWidth: 1)
                    }

                // The glow sits behind her and breathes with her, so the whole
                // stage feels alive rather than a lit figure on a dead panel.
                Circle()
                    .fill(RadialGradient(
                        colors: [renderer.moodTint.opacity(0.18 + renderer.glow * 0.15), .clear],
                        center: .center, startRadius: 0, endRadius: 180))
                    .frame(width: 340, height: 340)
                    .scaleEffect(1 + renderer.breath * 0.012)
                    .position(x: geo.size.width / 2, y: geo.size.height - 190)

                figure(in: geo.size)

                statusChips
                rigNotice
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    // Normalised to -1...1 so the renderer never has to know
                    // the size of the view it is drawn in.
                    look(at: CGPoint(
                        x: (point.x / geo.size.width) * 2 - 1,
                        y: (point.y / geo.size.height) * 2 - 1))
                case .ended:
                    look(at: nil)
                }
            }
        }
        .onAppear {
            loadRigIfNeeded()
            renderer.start()
            renderer.apply(state: state, mood: mood)
        }
        .onDisappear {
            renderer.stop()
            #if canImport(CubismBridge)
            if case .loaded(let live2d) = rig { live2d.stop() }
            #endif
        }
        // Driven from outside rather than by a method call: a View is a value,
        // so calling into a copy of it would silently do nothing.
        .onChange(of: state) { _, new in drive(state: new, mood: mood) }
        .onChange(of: mood) { _, new in drive(state: state, mood: new) }
    }

    /// Both renderers implement `CharacterRenderer`, so the stage drives
    /// whichever one is live through the same two calls. That protocol is the
    /// entire point of the seam — swapping the placeholder for a rig changes
    /// this file and no dashboard code.
    private func drive(state: CharacterState, mood: CharacterMood) {
        #if canImport(CubismBridge)
        if case .loaded(let live2d) = rig {
            live2d.apply(state: state, mood: mood)
            return
        }
        #endif
        renderer.apply(state: state, mood: mood)
    }

    private func look(at point: CGPoint?) {
        #if canImport(CubismBridge)
        if case .loaded(let live2d) = rig {
            live2d.look(at: point)
            return
        }
        #endif
        renderer.look(at: point)
    }

    /// The rig if it loaded, the procedural placeholder otherwise.
    @ViewBuilder
    private func figure(in size: CGSize) -> some View {
        #if canImport(CubismBridge)
        if case .loaded(let live2d) = rig {
            Live2DStageView(renderer: live2d)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 60)
        } else {
            character(in: size)
        }
        #else
        character(in: size)
        #endif
    }

    // MARK: Layers

    private func character(in size: CGSize) -> some View {
        ZStack {
            // Three layers is enough for real depth on cursor movement, and is
            // hours of separation work rather than the full 40-layer rig.
            layer(assets.hairBack, parallax: -0.5)
            layer(assets.body, parallax: 0)
            layer(assets.hairFront, parallax: 0.8)
            eyelids
            mouth
        }
        .scaleEffect(x: 1, y: 1 + renderer.breath * 0.005, anchor: .bottom)
        .rotationEffect(.degrees(renderer.sway.width * 0.15 + renderer.postureLean * 0.4),
                        anchor: .bottom)
        .offset(x: renderer.sway.width, y: renderer.sway.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 60)
    }

    @ViewBuilder
    private func layer(_ image: Image?, parallax: Double) -> some View {
        if let image {
            image
                .resizable()
                .scaledToFit()
                .offset(x: renderer.gaze.width * 14 * parallax,
                        y: renderer.gaze.height * 8 * parallax)
        } else {
            // No artwork yet: a silhouette that shows the composition and the
            // lighting design honestly, rather than a bad stand-in for her.
            PlaceholderSilhouette(tint: renderer.moodTint)
                .offset(x: renderer.gaze.width * 14 * parallax,
                        y: renderer.gaze.height * 8 * parallax)
        }
    }

    @ViewBuilder
    private var eyelids: some View {
        if let lids = assets.eyelids {
            lids.resizable().scaledToFit()
                .opacity(1 - renderer.eyeOpen)
        }
    }

    @ViewBuilder
    private var mouth: some View {
        if let shapes = assets.mouthFrames, !shapes.isEmpty {
            // Amplitude bands rather than a timer. With a Live2D rig this same
            // value drives ParamMouthOpenY continuously instead.
            let index = min(shapes.count - 1, Int(renderer.mouthOpen * Double(shapes.count)))
            shapes[index].resizable().scaledToFit()
        }
    }

    /// Shown only when a rig is configured and cannot be drawn. The
    /// placeholder renders regardless — nothing in the app waits on the art,
    /// which was the point of the seam.
    @ViewBuilder
    private var rigNotice: some View {
        if case .rigUnavailable(let reason) = resolution {
            VStack {
                Spacer()
                HStack(spacing: 7) {
                    Image(systemName: "person.crop.square.badge.camera")
                        .font(.system(size: 10))
                    Text("Placeholder — \(reason).")
                        .font(.system(size: 9.5))
                }
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(theme.surface.opacity(0.85)))
                .padding(.bottom, 14)
            }
        }
    }

    private var statusChips: some View {
        VStack {
            HStack {
                HStack(spacing: 7) {
                    Circle()
                        .fill(renderer.moodTint)
                        .frame(width: 6, height: 6)
                        .shadow(color: renderer.moodTint, radius: 5)
                    PanelLabel("Mood · \(renderer.mood.rawValue)")
                }
                Spacer()
            }
            Spacer()
        }
        .padding(16)
    }
}
/// Where the character's artwork comes from.
///
/// All optional: the app must render correctly before any of it exists, because
/// the rig is the longest-lead item on the project and nothing else should wait
/// on it.
public struct CharacterAssets: Sendable {
    public var body: Image?
    public var hairBack: Image?
    public var hairFront: Image?
    public var eyelids: Image?
    public var mouthFrames: [Image]?

    public init(body: Image? = nil, hairBack: Image? = nil, hairFront: Image? = nil,
                eyelids: Image? = nil, mouthFrames: [Image]? = nil) {
        self.body = body
        self.hairBack = hairBack
        self.hairFront = hairFront
        self.eyelids = eyelids
        self.mouthFrames = mouthFrames
    }

    public static let placeholder = CharacterAssets()
}

/// Stand-in geometry. Shows the composition, the rim lighting and the breathing
/// without pretending to be the character.
struct PlaceholderSilhouette: View {
    let tint: Color

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            var body = Path()
            body.move(to: CGPoint(x: w * 0.5, y: h * 0.28))
            body.addCurve(to: CGPoint(x: w * 0.70, y: h * 0.72),
                          control1: CGPoint(x: w * 0.68, y: h * 0.34),
                          control2: CGPoint(x: w * 0.72, y: h * 0.55))
            body.addLine(to: CGPoint(x: w * 0.30, y: h * 0.72))
            body.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.28),
                          control1: CGPoint(x: w * 0.28, y: h * 0.55),
                          control2: CGPoint(x: w * 0.32, y: h * 0.34))
            context.stroke(body, with: .color(tint.opacity(0.8)), lineWidth: 1.6)

            let head = Path(ellipseIn: CGRect(x: w * 0.38, y: h * 0.10,
                                              width: w * 0.24, height: h * 0.20))
            context.stroke(head, with: .color(tint.opacity(0.8)), lineWidth: 1.6)

            let ground = Path(ellipseIn: CGRect(x: w * 0.22, y: h * 0.94,
                                                width: w * 0.56, height: h * 0.04))
            context.fill(ground, with: .color(tint.opacity(0.18)))
        }
        .frame(width: 230, height: 400)
    }
}
