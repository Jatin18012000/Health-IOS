import Foundation
import Network
import AURACore

/// The phone side: find the Mac, send, read the receipt.
public actor SyncClient {

    public enum State: Sendable, Equatable {
        case idle
        case searching
        case sending(samples: Int)
        case finished(SyncProtocol.Receipt)
        case failed(String)
    }

    public private(set) var state: State = .idle

    private let pairingCode: String
    private let deviceName: String

    public init(pairingCode: String, deviceName: String) {
        self.pairingCode = pairingCode
        self.deviceName = deviceName
    }

    /// Send a batch and wait for the Mac to say what it did with it.
    ///
    /// The receipt is the point. A sync that reports "sent 4,000 samples" has
    /// told the user nothing about whether any of them landed; one that reports
    /// what was stored, what was already there and what was rejected is the
    /// same honesty the import screen already applies.
    public func send(_ samples: [Sample],
                     timeout: TimeInterval = 30) async throws -> SyncProtocol.Receipt {
        guard !samples.isEmpty else {
            return SyncProtocol.Receipt(stored: 0, duplicates: 0)
        }

        state = .searching
        let endpoint = try await findMac(timeout: timeout)

        state = .sending(samples: samples.count)
        let connection = NWConnection(
            to: endpoint, using: SyncSecurity.parameters(pairingCode: pairingCode))
        connection.start(queue: .global(qos: .utility))
        defer { connection.cancel() }

        let batch = SyncProtocol.Batch(
            deviceName: deviceName, samples: samples.map(SyncProtocol.WireSample.init))
        try await FrameReader.send(JSONEncoder().encode(batch), on: connection)

        let data = try await FrameReader.readFrame(on: connection)
        let receipt = try JSONDecoder().decode(SyncProtocol.Receipt.self, from: data)

        guard receipt.version == SyncProtocol.version else {
            throw SyncError.versionMismatch(theirs: receipt.version,
                                            ours: SyncProtocol.version)
        }
        state = .finished(receipt)
        return receipt
    }

    /// Browse for the service, take the first Mac that answers.
    ///
    /// Bonjour discovery rather than a stored address: a home network hands out
    /// a different one whenever the router feels like it, and a companion that
    /// needs an IP typed into it is a companion nobody uses twice.
    private func findMac(timeout: TimeInterval) async throws -> NWEndpoint {
        let browser = NWBrowser(
            for: .bonjour(type: SyncProtocol.serviceType, domain: nil),
            using: .tcp)
        defer { browser.cancel() }

        return try await withThrowingTaskGroup(of: NWEndpoint.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    let resumed = Resumed()
                    browser.browseResultsChangedHandler = { results, _ in
                        guard let first = results.first, resumed.claim() else { return }
                        continuation.resume(returning: first.endpoint)
                    }
                    browser.stateUpdateHandler = { state in
                        if case .failed(let error) = state, resumed.claim() {
                            continuation.resume(throwing: error)
                        }
                    }
                    browser.start(queue: .global(qos: .utility))
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw SyncError.noMacFound
            }

            guard let endpoint = try await group.next() else {
                throw SyncError.noMacFound
            }
            group.cancelAll()
            return endpoint
        }
    }
}

/// A continuation may be resumed exactly once, and both Bonjour handlers can
/// fire. Resuming twice is a crash, not a warning.
private final class Resumed: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
