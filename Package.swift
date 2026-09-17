// swift-tools-version: 6.0
import PackageDescription
import Foundation

// AURA is built as a set of local Swift packages plus a thin Xcode app target.
//
// The split is deliberate: everything except the app shell is a plain library
// with no AppKit/SwiftUI dependency where it can be avoided, so the same code
// compiles for a future iOS companion app (the only way to get automatic
// HealthKit sync -- HealthKit does not exist on macOS, see docs/ARCHITECTURE.md).
//
// Build and test from the command line with `swift build` / `swift test`.
// The app itself is an Xcode target that depends on this package -- see
// App/README.md for the one-time setup.

// MARK: - The Cubism SDK, if it is here

// The Live2D Cubism SDK for Native is a proprietary download that requires an
// account and agreeing to a licence, so it cannot live in this repository. The
// package therefore *detects* it rather than requiring it: with the SDK
// vendored, `CubismBridge` is built and `AURACharacter` links it; without, the
// package builds exactly as it did before and `Live2DRenderer` stays behind its
// `#if canImport(CubismBridge)` guard, drawing the procedural placeholder.
//
// The alternative — declaring the targets unconditionally — turns a working
// `swift build` into a broken one for anyone who has not downloaded a
// proprietary SDK, including CI. That is not a trade worth making for a
// character renderer.
//
// Run `tools/setup_cubism.sh` to check a download is laid out as expected.

let cubismRoot = Context.packageDirectory + "/Vendor/CubismSDK"
let hasCubism = FileManager.default.fileExists(
    atPath: cubismRoot + "/Core/include/Live2DCubismCore.h")

let cubismTargets: [Target] = hasCubism ? [
    // The Framework: Live2D's C++ layer over the Core. Vendored as source
    // because that is how the SDK ships it.
    //
    // No separate target for the Core itself. A `.systemLibrary` would need a
    // `module.modulemap` inside the SDK folder, and that folder is a download
    // this repository does not own — so the Core is reached by header search
    // path and linked as a plain library instead.
    .target(
        name: "CubismFramework",
        path: "Vendor/CubismSDK/Framework/src",
        // Only the Metal renderer. The SDK ships OpenGL, Vulkan, D3D and
        // Cocos2d backends in the same tree; compiling them costs build time
        // to produce code this app can never reach.
        exclude: [
            "Rendering/OpenGL", "Rendering/Vulkan", "Rendering/D3D9",
            "Rendering/D3D11", "Rendering/Cocos2d",
        ],
        cxxSettings: [
            .headerSearchPath("."),
            .headerSearchPath("../../Core/include"),
        ]),

    .target(
        name: "CubismBridge",
        dependencies: ["CubismFramework"],
        path: "Sources/CubismBridge",
        cxxSettings: [
            .headerSearchPath("../../Vendor/CubismSDK/Framework/src"),
            .headerSearchPath("../../Vendor/CubismSDK/Core/include"),
        ],
        linkerSettings: [
            // `unsafeFlags` is how a vendored `.a` gets onto the link line, and
            // it is acceptable only because AURA is a root package — SwiftPM
            // forbids unsafe flags in a package something else depends on. If
            // this is ever consumed as a dependency, this is what has to change.
            .unsafeFlags(["-L\(cubismRoot)/Core/lib/macos"]),
            .linkedLibrary("Live2DCubismCore"),
            .linkedFramework("Metal"),
            .linkedFramework("MetalKit"),
        ]),
] : []

let characterDependencies: [Target.Dependency] =
    ["AURACore", "AURADesign"] + (hasCubism ? ["CubismBridge"] : [])

let package = Package(
    name: "AURA",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),   // for the future HealthKit companion; no app target yet
    ],
    products: [
        .library(name: "AURACore",         targets: ["AURACore"]),
        .library(name: "AURAIngest",       targets: ["AURAIngest"]),
        .library(name: "AURAStore",        targets: ["AURAStore"]),
        .library(name: "AURAAnalytics",    targets: ["AURAAnalytics"]),
        .library(name: "AURAMemory",       targets: ["AURAMemory"]),
        .library(name: "AURAReport",       targets: ["AURAReport"]),
        .library(name: "AURAIntelligence", targets: ["AURAIntelligence"]),
        .library(name: "AURAVoice",        targets: ["AURAVoice"]),
        .library(name: "AURACharacter",    targets: ["AURACharacter"]),
        .library(name: "AURADesign",       targets: ["AURADesign"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),

        // The local LLM. Note this is mlx-swift-lm, NOT the older
        // mlx-swift-examples -- the model-loading API moved there and the
        // factory call changed shape with it.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "2.21.0"),

        // Speech-to-text. MIT-licensed; the push-to-talk path uses only the
        // open-source surface. (Argmax's paid tier buys low-latency STREAMING
        // transcription, which push-to-talk does not need.)
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),

        // Local neural TTS. Apache 2.0, model and code both. 82M parameters and
        // it runs on the Neural Engine, so it barely contends with the language
        // model holding the GPU.
        .package(url: "https://github.com/mweinbach/kokoro-swift", from: "0.1.0"),
    ],
    targets: [
        // Domain vocabulary. Depends on nothing. Everything depends on it.
        .target(name: "AURACore"),

        // SQLite persistence + the Parquet archive tier.
        .target(name: "AURAStore", dependencies: [
            "AURACore",
            .product(name: "GRDB", package: "GRDB.swift"),
        ]),

        // Apple Health export -> normalized samples -> the store.
        // Depends on AURAStore because ingest is the layer that writes.
        .target(name: "AURAIngest", dependencies: ["AURACore", "AURAStore"]),

        // Rollups, trends, correlations, scores, anomaly detection.
        // All arithmetic lives here -- never in a prompt. See docs/INTELLIGENCE.md.
        .target(name: "AURAAnalytics", dependencies: ["AURACore", "AURAStore"]),

        // What she remembers: confirmed facts, context annotations,
        // conversation history. Its own database — see MemoryStore.
        .target(name: "AURAMemory", dependencies: [
            "AURACore",
            .product(name: "GRDB", package: "GRDB.swift"),
        ]),

        // The doctor-facing PDF. Contains no generated prose — see HealthReport.
        .target(name: "AURAReport", dependencies: [
            "AURACore", "AURAAnalytics", "AURAMemory",
        ]),

        // LLM provider abstraction, context building, output safety.
        //
        // MLX is linked here, but MLXModel is behind `#if canImport(MLXLLM)`
        // so the module still builds and tests without it -- the guard, the
        // brief and the sentence stream are all testable with no weights on
        // the machine.
        .target(name: "AURAIntelligence", dependencies: [
            "AURACore", "AURAAnalytics", "AURAMemory",
            .product(name: "MLXLLM", package: "mlx-swift-lm"),
            .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
        ]),

        // Text-to-speech, speech-to-text, and the audio level tap that drives
        // her mouth. Protocol-first so the engine can be swapped.
        //
        // WhisperKit sits behind `#if canImport`, so the module builds and the
        // app runs with typing as the only input when it is absent.
        .target(name: "AURAVoice", dependencies: [
            "AURACore",
            .product(name: "WhisperKit", package: "WhisperKit"),
            .product(name: "Kokoro", package: "kokoro-swift"),
        ]),

        // The companion: mood state machine, sprite renderer, Live2D seam.
        //
        // `CubismBridge` is in this list only when the SDK is vendored; see the
        // detection above. `Live2DRenderer` guards on `canImport(CubismBridge)`
        // so the module compiles either way.
        .target(name: "AURACharacter", dependencies: characterDependencies),

        // Theme tokens, neon/glass components, chart styling.
        .target(name: "AURADesign", dependencies: ["AURACore"]),

        .testTarget(name: "AURAIngestTests",    dependencies: ["AURAIngest"]),
        .testTarget(name: "AURAAnalyticsTests", dependencies: ["AURAAnalytics"]),
        .testTarget(name: "AURACoreTests",      dependencies: ["AURACore"]),
        .testTarget(name: "AURAIntelligenceTests", dependencies: ["AURAIntelligence"]),
        .testTarget(name: "AURAMemoryTests",       dependencies: ["AURAMemory"]),
        .testTarget(name: "AURAStoreTests",        dependencies: ["AURAStore"]),
        .testTarget(name: "AURACharacterTests",    dependencies: ["AURACharacter"]),
        // AURACore/Analytics/Memory are declared rather than leaned on
        // transitively: the suite builds its own store double and its own
        // annotations, so it imports all three directly.
        .testTarget(name: "AURAReportTests", dependencies: [
            "AURAReport", "AURACore", "AURAAnalytics", "AURAMemory",
        ]),
    ] + cubismTargets
)
