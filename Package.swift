// swift-tools-version: 6.0
import PackageDescription

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

        // LLM provider abstraction, context building, output safety.
        //
        // MLX is linked here, but MLXModel is behind `#if canImport(MLXLLM)`
        // so the module still builds and tests without it -- the guard, the
        // brief and the sentence stream are all testable with no weights on
        // the machine.
        .target(name: "AURAIntelligence", dependencies: [
            "AURACore", "AURAAnalytics",
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
        ]),

        // The companion: mood state machine, sprite renderer, Live2D seam.
        .target(name: "AURACharacter", dependencies: ["AURACore", "AURADesign"]),

        // Theme tokens, neon/glass components, chart styling.
        .target(name: "AURADesign", dependencies: ["AURACore"]),

        .testTarget(name: "AURAIngestTests",    dependencies: ["AURAIngest"]),
        .testTarget(name: "AURAAnalyticsTests", dependencies: ["AURAAnalytics"]),
        .testTarget(name: "AURACoreTests",      dependencies: ["AURACore"]),
        .testTarget(name: "AURAIntelligenceTests", dependencies: ["AURAIntelligence"]),
    ]
)
