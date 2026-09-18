import Foundation
import Network
import CryptoKit
import AURACore

/// TLS with a pre-shared key, for both ends.
///
/// Kept in one place because the two sides must agree exactly: a mismatch in
/// the key, the cipher suite or the identity string is a handshake failure with
/// a message that names none of those things.
enum SyncSecurity {

    static func parameters(pairingCode: String) -> NWParameters {
        let options = NWProtocolTLS.Options()
        let key = SyncProtocol.key(fromPairingCode: pairingCode)

        // Both ends must present the same key AND the same identity hint, or
        // the handshake fails with an error that names neither.
        let keyData = key.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data("AURA".utf8).withUnsafeBytes { DispatchData(bytes: $0) }

        // `sec_protocol_options_add_pre_shared_key` is a C API and takes
        // `dispatch_data_t` (aka `__DispatchData`) -- the Objective-C class
        // backing Dispatch's C interop, not Swift's `DispatchData` value type
        // itself. `as __DispatchData` is the bridge; `keyData` is already a
        // `DispatchData`, so casting it "as DispatchData" (with or without
        // `any`, which does not apply to a concrete struct) was a no-op that
        // never reached the type the C function actually declares.
        sec_protocol_options_add_pre_shared_key(
            options.securityProtocolOptions, keyData as __DispatchData,
            identity as __DispatchData)

        // A TLS 1.3 suite, which is what PSK uses here. The older
        // `TLS_PSK_WITH_*` constants are Security-framework SSLCipherSuite
        // values and do not belong in this API.
        sec_protocol_options_append_tls_ciphersuite(
            options.securityProtocolOptions, .AES_128_GCM_SHA256)

        let parameters = NWParameters(tls: options)
        // The phone and the Mac are on the same Wi-Fi; there is no reason to
        // let this path wander onto cellular and there is a reason not to.
        parameters.prohibitedInterfaceTypes = [.cellular]
        parameters.includePeerToPeer = true
        return parameters
    }
}

/// Reads length-prefixed frames off a connection.
///
/// Its own type because the mistake it prevents is easy to make and hard to
/// see: `receive(minimumIncompleteLength:maximumLength:)` will happily hand
/// back a partial frame, and code that assumes otherwise works perfectly on a
/// local network with small payloads and fails the first time a batch is large
/// enough to be split across packets.
struct FrameReader {

    static func readFrame(on connection: NWConnection) async throws -> Data {
        let header = try await readExactly(SyncProtocol.headerLength, on: connection)
        guard let length = SyncProtocol.frameLength(header: header) else {
            throw SyncError.malformedFrame
        }
        return try await readExactly(length, on: connection)
    }

    private static func readExactly(_ count: Int,
                                    on connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: count,
                               maximumLength: count) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, data.count == count {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: SyncError.connectionClosed)
                }
            }
        }
    }

    static func send(_ payload: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            connection.send(content: SyncProtocol.frame(payload),
                            completion: .contentProcessed { error in
                if let error { c.resume(throwing: error) } else { c.resume() }
            })
        }
    }
}

public enum SyncError: Error, Sendable, LocalizedError {
    case malformedFrame
    case connectionClosed
    case versionMismatch(theirs: Int, ours: Int)
    case notPaired
    case noMacFound

    public var errorDescription: String? {
        switch self {
        case .malformedFrame:
            "The other device sent something this version doesn't understand."
        case .connectionClosed:
            "The connection closed before the sync finished."
        case .versionMismatch(let theirs, let ours):
            "That Mac is running sync version \(theirs) and this phone is on \(ours). Update both."
        case .notPaired:
            "This phone hasn't been paired with a Mac yet."
        case .noMacFound:
            "No paired Mac found on this network. Check AURA is open on the Mac and both are on the same Wi-Fi."
        }
    }
}
