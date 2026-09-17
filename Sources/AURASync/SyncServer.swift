import Foundation
import Network
import AURACore

/// The Mac side: advertise, accept, ingest, reply.
///
/// Runs only while the app is open. That is not a limitation to apologise for —
/// a health companion that keeps a listener alive in the background so a phone
/// can reach it is a different and less welcome product, and the same reasoning
/// already governs `MorningBriefScheduler`.
public actor SyncServer {

    public enum State: Sendable, Equatable {
        case stopped
        case advertising(pairingCode: String)
        case receiving(from: String)
        case failed(String)
    }

    /// Hands a received batch to whatever knows how to store it.
    ///
    /// A closure rather than a store dependency: this module has no business
    /// importing `AURAStore`, and keeping transport free of persistence is what
    /// lets the whole thing be tested without a database.
    public typealias Ingest = @Sendable ([Sample]) async -> SyncProtocol.Receipt

    private var listener: NWListener?
    private var code: String?
    private let ingest: Ingest
    private var onState: @Sendable (State) -> Void

    public private(set) var state: State = .stopped {
        didSet { onState(state) }
    }

    public init(ingest: @escaping Ingest,
                onState: @escaping @Sendable (State) -> Void = { _ in }) {
        self.ingest = ingest
        self.onState = onState
    }

    /// Start advertising, returning the code to show the user.
    public func start(pairingCode: String = SyncProtocol.pairingCode()) throws -> String {
        stop()
        code = pairingCode

        let listener = try NWListener(
            using: SyncSecurity.parameters(pairingCode: pairingCode))
        // The name is the Mac's, so a phone paired with two Macs can tell them
        // apart. It carries nothing secret; the pairing code is what matters.
        // `ProcessInfo`, not `Host`: the latter is macOS-only and this target
        // compiles for the phone as well.
        listener.service = NWListener.Service(
            name: ProcessInfo.processInfo.hostName,
            type: SyncProtocol.serviceType)

        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.handle(connection) }
        }
        listener.stateUpdateHandler = { [weak self] newState in
            Task { await self?.listenerChanged(newState) }
        }

        self.listener = listener
        listener.start(queue: .global(qos: .utility))
        state = .advertising(pairingCode: pairingCode)
        return pairingCode
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        code = nil
        state = .stopped
    }

    private func listenerChanged(_ newState: NWListener.State) {
        if case .failed(let error) = newState {
            state = .failed(error.localizedDescription)
        }
    }

    private func handle(_ connection: NWConnection) async {
        connection.start(queue: .global(qos: .utility))
        defer { connection.cancel() }

        do {
            let data = try await FrameReader.readFrame(on: connection)
            let batch = try JSONDecoder().decode(SyncProtocol.Batch.self, from: data)

            guard batch.version == SyncProtocol.version else {
                // Refused rather than best-effort decoded. Two versions
                // disagreeing about a field is how a sample lands under the
                // wrong metric, and that is worse than a failed sync.
                let receipt = SyncProtocol.Receipt(
                    stored: 0, duplicates: 0,
                    failure: "sync version \(batch.version) is not \(SyncProtocol.version)")
                try await reply(receipt, on: connection)
                return
            }

            state = .receiving(from: batch.deviceName)
            let receipt = await ingest(batch.samples.map(\.sample))
            try await reply(receipt, on: connection)

            if let code { state = .advertising(pairingCode: code) }
        } catch {
            // One bad connection must not stop the listener; the phone will try
            // again and the user is told on that side.
            if let code { state = .advertising(pairingCode: code) }
        }
    }

    private func reply(_ receipt: SyncProtocol.Receipt,
                       on connection: NWConnection) async throws {
        try await FrameReader.send(JSONEncoder().encode(receipt), on: connection)
    }
}
