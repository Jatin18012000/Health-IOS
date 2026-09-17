import Foundation
import AURACore

#if canImport(HealthKit)
import HealthKit

/// Reads new HealthKit samples since the last time it was asked.
///
/// The whole point of the companion. HealthKit does not exist on macOS, so a
/// manual export is the Mac's only route in; on a phone the data is already
/// there and can be read incrementally.
///
/// ## What this deliberately does not do
///
/// **No aggregation, no deduplication, no rollups.** It emits raw
/// `AURACore.Sample` values and sends them to the Mac, which runs them through
/// the same `SQLiteHealthStore.ingest` path an XML import uses. That is not
/// laziness — a second aggregation path would be a second place for the
/// multi-source deduplication to be subtly different, and `CLAUDE.md` makes
/// that deduplication an invariant because getting it wrong inflates real days
/// by up to 1.9x. One pipeline, one set of rules, exercised by the conformance
/// suite either way.
public actor HealthKitReader {

    public struct Progress: Sendable {
        public let type: String
        public let samples: Int
    }

    public enum ReadError: Error, Sendable, LocalizedError {
        case unavailable
        case denied

        public var errorDescription: String? {
            switch self {
            case .unavailable:
                "Health data isn't available on this device."
            case .denied:
                "AURA hasn't been given permission to read Health data. Grant it in Settings → Health → Data Access & Devices."
            }
        }
    }

    private let store = HKHealthStore()
    private let anchors: AnchorStore

    public init(anchorsAt url: URL) {
        self.anchors = AnchorStore(url: url)
    }

    // MARK: Authorisation

    /// Ask once for read access to everything in the catalog.
    ///
    /// Read authorisation in HealthKit is deliberately opaque: the system never
    /// tells an app whether reading was granted, only whether the sheet was
    /// shown, because "you were denied" would itself leak that the data exists.
    /// So there is no point checking a status afterwards — an empty result is
    /// indistinguishable from a denial, and the UI has to say so honestly
    /// rather than claiming everything synced.
    public func requestAuthorisation() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw ReadError.unavailable }

        var types: Set<HKObjectType> = []
        types.formUnion(HealthKitUnits.quantityTypes().keys.map { $0 as HKObjectType })
        types.formUnion(HealthKitUnits.categoryTypes().keys.map { $0 as HKObjectType })

        try await store.requestAuthorization(toShare: [], read: types)
    }

    // MARK: Reading

    /// Everything new since the last call, type by type.
    ///
    /// Anchored rather than date-windowed. A date window re-reads the same
    /// samples every run and relies on the store's idempotency to absorb them,
    /// which works but sends four years of data over the network to discover
    /// that 99.99% of it is already there. An anchor asks HealthKit for the
    /// delta, so a routine sync is a few hundred samples.
    public func newSamples(
        onProgress: @Sendable (Progress) -> Void = { _ in }
    ) async throws -> [Sample] {
        guard HKHealthStore.isHealthDataAvailable() else { throw ReadError.unavailable }

        var collected: [Sample] = []

        for (type, metric) in HealthKitUnits.quantityTypes() {
            guard let unit = HealthKitUnits.hkUnit(for: metric.unit) else { continue }
            let (objects, anchor) = try await read(type: type)
            let samples = objects.compactMap { object -> Sample? in
                guard let quantity = (object as? HKQuantitySample)?.quantity else { return nil }
                return Sample(
                    metric: metric.id,
                    value: quantity.doubleValue(for: unit),
                    source: object.sourceRevision.source.name,
                    device: object.device?.name,
                    start: object.startDate,
                    end: object.endDate)
            }
            collected.append(contentsOf: samples)
            await anchors.set(anchor, for: type.identifier)
            onProgress(Progress(type: metric.id, samples: samples.count))
        }

        for (type, metric) in HealthKitUnits.categoryTypes() {
            let (objects, anchor) = try await read(type: type)
            let samples = objects.compactMap { object -> Sample? in
                guard let category = object as? HKCategorySample else { return nil }
                // Sleep is the only category whose value carries meaning the
                // pipeline reads. Others are presence, and the XML export
                // writes their raw value, so it is passed through the same way.
                let raw = metric.id == "SleepAnalysis"
                    ? HealthKitUnits.sleepCategory(category.value)
                    : String(category.value)
                guard let raw else { return nil }
                return Sample(
                    metric: metric.id,
                    value: nil,
                    category: raw,
                    source: object.sourceRevision.source.name,
                    device: object.device?.name,
                    start: object.startDate,
                    end: object.endDate)
            }
            collected.append(contentsOf: samples)
            await anchors.set(anchor, for: type.identifier)
            onProgress(Progress(type: metric.id, samples: samples.count))
        }

        return collected
    }

    /// One anchored query, bridged to async.
    ///
    /// Deletions are requested and then discarded. `SQLiteHealthStore` has no
    /// delete path — the store is append-only by design, and a sample removed
    /// on the phone stays in the Mac's history. That is a real divergence and
    /// it is left visible here rather than hidden: see the companion's README.
    private func read(type: HKSampleType) async throws -> ([HKSample], HKQueryAnchor?) {
        let previous = await anchors.get(for: type.identifier)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: type, predicate: nil, anchor: previous,
                limit: HKObjectQueryNoLimit
            ) { _, samples, _, newAnchor, error in
                if let error {
                    // A type the user has not authorised errors rather than
                    // returning empty. One refused type must not abort the
                    // whole sync, so it is reported as nothing to send.
                    let denied = (error as? HKError)?.code == .errorAuthorizationDenied
                    if denied {
                        continuation.resume(returning: ([], previous))
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                continuation.resume(returning: (samples ?? [], newAnchor))
            }
            store.execute(query)
        }
    }

    /// Forget every anchor, so the next read returns the full history.
    ///
    /// For the case where the Mac's database was restored from a backup older
    /// than the phone's anchors: the anchors would say "nothing new" while the
    /// store is missing months.
    public func resetAnchors() async {
        await anchors.clear()
    }
}

/// Where the anchors live between launches.
///
/// One file, archived. Losing it costs a full re-read, which the Mac absorbs as
/// duplicates — so this is a cache, not data, and it deliberately never fails
/// loudly.
actor AnchorStore {
    private let url: URL
    private var anchors: [String: Data]

    init(url: URL) {
        self.url = url
        self.anchors = (try? JSONDecoder().decode(
            [String: Data].self, from: Data(contentsOf: url))) ?? [:]
    }

    func get(for identifier: String) -> HKQueryAnchor? {
        guard let data = anchors[identifier] else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: HKQueryAnchor.self, from: data)
    }

    func set(_ anchor: HKQueryAnchor?, for identifier: String) {
        guard let anchor,
              let data = try? NSKeyedArchiver.archivedData(
                  withRootObject: anchor, requiringSecureCoding: true)
        else { return }
        anchors[identifier] = data
        persist()
    }

    func clear() {
        anchors = [:]
        persist()
    }

    private func persist() {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(anchors).write(to: url, options: .atomic)
    }
}
#endif
