import Testing
import Foundation
import AURACore
@testable import AURASync

/// The wire format, which is the part of sync that can be checked without a
/// phone, a Mac and a network between them.
///
/// Worth checking carefully for one reason: everything else in this project can
/// be re-derived from the export if it goes wrong. A sample that crosses the
/// wire mangled is stored mangled, beside four years of correct data, with
/// nothing to compare it against.
@Suite("Sync wire format")
struct SyncProtocolTests {

    // MARK: Framing

    @Test("a frame declares its own length")
    func frameRoundTrip() throws {
        let payload = Data("hello".utf8)
        let framed = SyncProtocol.frame(payload)

        #expect(framed.count == SyncProtocol.headerLength + payload.count)
        let header = framed.prefix(SyncProtocol.headerLength)
        #expect(SyncProtocol.frameLength(header: Data(header)) == payload.count)
        #expect(framed.dropFirst(SyncProtocol.headerLength) == payload)
    }

    @Test("an absurd length is refused before anything is allocated for it")
    func rejectsAbsurdLengths() {
        // A hostile or corrupt header asking for 4 GB must not cause the
        // receiver to reserve 4 GB and find out afterwards.
        var huge = Data()
        var length = UInt32(SyncProtocol.maximumFrame + 1).bigEndian
        withUnsafeBytes(of: &length) { huge.append(contentsOf: $0) }
        #expect(SyncProtocol.frameLength(header: huge) == nil)

        var zero = Data()
        var none = UInt32(0).bigEndian
        withUnsafeBytes(of: &none) { zero.append(contentsOf: $0) }
        // A zero-length frame is not a message; treating it as one is a loop
        // that reads nothing forever.
        #expect(SyncProtocol.frameLength(header: zero) == nil)
    }

    @Test("a short or empty header is not a length")
    func rejectsShortHeaders() {
        #expect(SyncProtocol.frameLength(header: Data()) == nil)
        #expect(SyncProtocol.frameLength(header: Data([0, 0, 1])) == nil)
    }

    @Test("the length is big-endian, so two machines agree on it")
    func headerIsBigEndian() {
        let framed = SyncProtocol.frame(Data(repeating: 0, count: 258))
        // 258 = 0x0102. Little-endian would put 0x02 first and a peer reading
        // big-endian would wait for 33 million bytes that never arrive.
        #expect(Array(framed.prefix(4)) == [0x00, 0x00, 0x01, 0x02])
    }

    // MARK: Samples

    @Test("a sample survives the round trip unchanged")
    func sampleRoundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_741_600_000)
        let original = Sample(metric: "StepCount", value: 1234.5,
                              source: "Jatin's Apple Watch", device: "Watch7,1",
                              start: start, end: start.addingTimeInterval(3600))

        let wire = SyncProtocol.WireSample(original)
        let encoded = try JSONEncoder().encode(wire)
        let decoded = try JSONDecoder().decode(SyncProtocol.WireSample.self, from: encoded)
        let restored = decoded.sample

        #expect(restored.metric == original.metric)
        #expect(restored.value == original.value)
        #expect(restored.source == original.source)
        #expect(restored.device == original.device)
        // Seconds since 1970 as a Double. Exact for any date this century, and
        // the source name has to survive verbatim — `SourceResolver` matches on
        // it, and a mangled name ranks the Watch as unknown, which inverts every
        // deduplicated total.
        #expect(restored.start == original.start)
        #expect(restored.end == original.end)
    }

    @Test("a category sample keeps its category and carries no value")
    func categorySampleRoundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_741_600_000)
        let original = Sample(metric: "SleepAnalysis", value: nil,
                              category: "HKCategoryValueSleepAnalysisAsleepDeep",
                              source: "Apple Watch", start: start,
                              end: start.addingTimeInterval(1800))

        let restored = SyncProtocol.WireSample(original).sample
        // The sleep pipeline keys on this exact string to tell a staged night
        // from an in-bed-only one, and `CLAUDE.md` makes that separation an
        // invariant. A category that arrives altered silently re-classifies the
        // night.
        #expect(restored.category == "HKCategoryValueSleepAnalysisAsleepDeep")
        #expect(restored.value == nil)
    }

    @Test("a batch declares the protocol version it was written by")
    func batchCarriesVersion() throws {
        let batch = SyncProtocol.Batch(deviceName: "iPhone", samples: [])
        let decoded = try JSONDecoder().decode(
            SyncProtocol.Batch.self, from: JSONEncoder().encode(batch))
        #expect(decoded.version == SyncProtocol.version)
        #expect(decoded.deviceName == "iPhone")
    }

    @Test("a receipt reports what the Mac actually did")
    func receiptRoundTrip() throws {
        let receipt = SyncProtocol.Receipt(
            stored: 12, duplicates: 4_000, rejected: ["unmapped:Foo": 2])
        let decoded = try JSONDecoder().decode(
            SyncProtocol.Receipt.self, from: JSONEncoder().encode(receipt))

        #expect(decoded.stored == 12)
        // The number that needs reporting rather than hiding: most of a sync is
        // data the Mac already has, and that is the pipeline working.
        #expect(decoded.duplicates == 4_000)
        #expect(decoded.rejected["unmapped:Foo"] == 2)
        #expect(decoded.failure == nil)
    }

    // MARK: Pairing

    @Test("a pairing code is always six digits")
    func pairingCodeShape() {
        for _ in 0..<200 {
            let code = SyncProtocol.pairingCode()
            #expect(code.count == 6)
            #expect(code.allSatisfy(\.isNumber))
        }
    }

    @Test("the same code derives the same key, a different code does not")
    func keyDerivation() {
        // Both ends derive independently and never exchange the key; if this
        // were not deterministic no two devices could ever pair.
        let a = SyncProtocol.key(fromPairingCode: "123456")
        let b = SyncProtocol.key(fromPairingCode: "123456")
        let c = SyncProtocol.key(fromPairingCode: "123457")

        #expect(a == b)
        #expect(a != c)
        #expect(a.bitCount == 256)
    }

    @Test("the service name says nothing about health")
    func serviceIsUninteresting() {
        // Bonjour advertisements are visible to everyone on the network. The
        // name grants nothing and should reveal nothing either.
        #expect(!SyncProtocol.serviceType.lowercased().contains("health"))
        #expect(SyncProtocol.serviceType.hasSuffix("._tcp"))
    }
}
