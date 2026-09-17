import SwiftUI
import UIKit
import AURACore
import AURAHealthKit
import AURASync

/// The iOS companion.
///
/// One job: read what HealthKit has that the Mac does not, and hand it over.
/// It shows no figures, computes nothing, and has no opinion about the data —
/// the Mac holds the store and all the arithmetic lives in `AURAAnalytics`.
/// A second place that aggregated would be a second place to get the
/// multi-source deduplication subtly wrong.
@main
struct CompanionApp: App {
    @State private var model = CompanionModel()

    var body: some Scene {
        WindowGroup {
            CompanionView(model: model)
        }
    }
}

@Observable
@MainActor
final class CompanionModel {

    enum Phase: Equatable {
        case needsPairing
        case ready
        case working(String)
        case done(stored: Int, duplicates: Int, at: Date)
        case failed(String)
    }

    private(set) var phase: Phase = .needsPairing
    var pairingCode = ""

    /// Stored in the keychain rather than `UserDefaults`: it is the only secret
    /// on this device, and a preferences plist is world-readable to anything
    /// with a backup of the phone.
    @ObservationIgnored private let keychain = PairingKeychain()
    @ObservationIgnored private lazy var reader = HealthKitReader(anchorsAt: Self.anchorsURL)

    static var anchorsURL: URL {
        URL.applicationSupportDirectory.appending(path: "AURA/anchors.json")
    }

    init() {
        if keychain.code != nil { phase = .ready }
    }

    var isPaired: Bool { keychain.code != nil }

    func pair() {
        let code = pairingCode.filter(\.isNumber)
        guard code.count == 6 else {
            phase = .failed("A pairing code is six digits.")
            return
        }
        keychain.code = code
        pairingCode = ""
        phase = .ready
    }

    func unpair() {
        keychain.code = nil
        phase = .needsPairing
    }

    /// Ask for Health access, read the delta, send it, report what the Mac did.
    func sync() async {
        guard let code = keychain.code else {
            phase = .failed(SyncError.notPaired.localizedDescription)
            return
        }

        do {
            phase = .working("Asking for Health access")
            try await reader.requestAuthorisation()

            phase = .working("Reading what's new")
            let samples = try await reader.newSamples()

            guard !samples.isEmpty else {
                // Not an error and not a success worth celebrating. Anchored
                // reads mean this is the normal state most of the time.
                phase = .done(stored: 0, duplicates: 0, at: Date())
                return
            }

            phase = .working("Sending \(samples.count.formatted()) samples")
            let client = SyncClient(pairingCode: code,
                                    deviceName: UIDevice.current.name)
            let receipt = try await client.send(samples)

            if let failure = receipt.failure {
                phase = .failed(failure)
            } else {
                phase = .done(stored: receipt.stored,
                              duplicates: receipt.duplicates, at: Date())
            }
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription
                            ?? error.localizedDescription)
        }
    }

    /// Re-read everything from the beginning.
    ///
    /// For the case where the Mac was restored from a backup older than this
    /// phone's anchors — the anchors would say "nothing new" while the store is
    /// months behind. The Mac absorbs the re-read as duplicates.
    func resendEverything() async {
        await reader.resetAnchors()
        await sync()
    }
}
