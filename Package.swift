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

        // Uncommented at the milestones that need them -- kept out of the
        // initial graph so a fresh clone builds fast with no large checkouts.
        // M5 (local LLM):   .package(url: "https://github.com/ml-explore/mlx-swift-examples", from: "2.0.0"),
        // M6 (speech-to-text): .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
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
        .target(name: "AURAIntelligence", dependencies: ["AURACore", "AURAAnalytics"]),

        // Text-to-speech, speech-to-text, and the audio level tap that drives
        // her mouth. Protocol-first so the engine can be swapped.
        .target(name: "AURAVoice", dependencies: ["AURACore"]),

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
