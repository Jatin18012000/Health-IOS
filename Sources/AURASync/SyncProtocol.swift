import Foundation
import CryptoKit
import AURACore

/// What crosses the wire, and the rules for putting it there.
///
/// ## The security shape, stated plainly
///
/// This is the one place in AURA where health data leaves a device. The project
/// otherwise has no network path at all, so the bar is not "encrypted in
/// transit" — it is "a device that is not the paired Mac cannot read or inject
/// anything, even on a hostile network".
///
/// That is met with TLS using a **pre-shared key** derived from a pairing code
/// the user reads off one screen and types into the other. No certificates, no
/// trust-on-first-use, no accounts: a peer either derives the same key from the
/// same code or the handshake fails. It also means the Bonjour advertisement
/// can be entirely uninteresting to anyone watching, because possession of the
/// service name grants nothing.
///
/// The pairing code is never transmitted. Only something derived from it is.
public enum SyncProtocol {

    /// The Bonjour service. Deliberately says nothing about health.
    public static let serviceType = "_aura-sync._tcp"

    /// Bumped when the payload shape changes. A mismatch is refused rather than
    /// guessed at, because a phone and a Mac on different versions disagreeing
    /// about a field is how a sample gets stored under the wrong metric.
    public static let version = 1

    /// A batch of samples, as sent.
    public struct Batch: Codable, Sendable {
        public let version: Int
        public let deviceName: String
        public let samples: [WireSample]

        public init(deviceName: String, samples: [WireSample]) {
            self.version = SyncProtocol.version
            self.deviceName = deviceName
            self.samples = samples
        }
    }

    /// What the Mac says back.
    public struct Receipt: Codable, Sendable, Equatable {
        public let version: Int
        public let stored: Int
        public let duplicates: Int
        public let rejected: [String: Int]
        /// Set when the Mac refused the batch outright.
        public let failure: String?

        public init(stored: Int, duplicates: Int,
                    rejected: [String: Int] = [:], failure: String? = nil) {
            self.version = SyncProtocol.version
            self.stored = stored
            self.duplicates = duplicates
            self.rejected = rejected
            self.failure = failure
        }
    }

    /// `AURACore.Sample` is not `Codable`, and making it so would put a wire
    /// format on a domain type — a field renamed for clarity in the model would
    /// then silently break every phone that had not been updated. This is the
    /// wire format, and it is allowed to be ugly and stable.
    public struct WireSample: Codable, Sendable {
        public let m: String        // metric id
        public let v: Double?       // value
        public let c: String?       // category
        public let s: String        // source name
        public let d: String?       // device
        public let a: Double        // start, seconds since 1970
        public let b: Double        // end

        public init(_ sample: Sample) {
            self.m = sample.metric
            self.v = sample.value
            self.c = sample.category
            self.s = sample.source
            self.d = sample.device
            self.a = sample.start.timeIntervalSince1970
            self.b = sample.end.timeIntervalSince1970
        }

        public var sample: Sample {
            Sample(metric: m, value: v, category: c, source: s, device: d,
                   start: Date(timeIntervalSince1970: a),
                   end: Date(timeIntervalSince1970: b))
        }
    }

    // MARK: Pairing

    /// Six digits, read off the Mac and typed into the phone.
    ///
    /// Short enough to type without resentment, and it does not need to be
    /// longer: it is used once, over a local network, to derive a key for a
    /// connection that either succeeds immediately or does not. There is no
    /// oracle to grind against — a wrong code fails the TLS handshake, and the
    /// Mac can stop advertising after a few failures.
    public static func pairingCode() -> String {
        String(format: "%06d", Int.random(in: 0..<1_000_000))
    }

    /// Pairing code -> the pre-shared key both ends use.
    ///
    /// HKDF with a fixed, non-secret salt. The same caveat applies as to
    /// `Backup.derive`: HKDF is fast, which is right for expanding a key and
    /// wrong for resisting a grind against a low-entropy input. Six digits is
    /// low-entropy. What makes it acceptable here and not there is that a
    /// backup file can be taken away and attacked offline for a year, while
    /// this code authorises one connection on one local network and can be
    /// rotated by pressing a button.
    public static func key(fromPairingCode code: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(code.utf8)),
            salt: Data("aura.sync.v1".utf8),
            info: Data("pre-shared-key".utf8),
            outputByteCount: 32)
    }

    // MARK: Framing

    /// Length-prefixed frames: four bytes big-endian, then that many bytes.
    ///
    /// TCP is a stream, not a sequence of messages. Without a frame header a
    /// reader cannot tell one batch from two, and "read until the connection
    /// closes" turns every sync into a new connection.
    public static let headerLength = 4

    /// Refuses absurd lengths before allocating for them, so a malformed or
    /// hostile header cannot ask the receiver to reserve gigabytes.
    public static let maximumFrame = 32 * 1024 * 1024

    public static func frame(_ payload: Data) -> Data {
        var out = Data(capacity: headerLength + payload.count)
        var length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &length) { out.append(contentsOf: $0) }
        out.append(payload)
        return out
    }

    /// Length of the frame a header describes, or nil if it is not plausible.
    public static func frameLength(header: Data) -> Int? {
        guard header.count == headerLength else { return nil }
        let length = header.withUnsafeBytes { raw in
            Int(UInt32(bigEndian: raw.loadUnaligned(as: UInt32.self)))
        }
        return (1...maximumFrame).contains(length) ? length : nil
    }
}
