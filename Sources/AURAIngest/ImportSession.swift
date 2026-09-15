import Foundation
import AURACore
import AURAStore

/// Drives a full import: parse, store, rebuild the affected rollups.
///
/// The one entry point the UI needs. Everything it reports is a real count from
/// the pipeline rather than a spinner — importing four years of someone's health
/// data should be able to say exactly what it did.
public actor ImportSession {

    public struct Outcome: Sendable {
        public let recordsParsed: Int
        public let samplesStored: Int
        /// Records already present. On a second import of an overlapping export
        /// this is nearly all of them, and that is success, not a problem.
        public let duplicates: Int
        public let rejected: [String: Int]
        public let daysAffected: DayRange?
        public let duration: TimeInterval

        public var hasIssues: Bool { !rejected.isEmpty }
    }

    public enum State: Sendable, Equatable {
        case idle
        case parsing(fraction: Double, records: Int)
        case rebuilding(days: Int)
        case finished
        case failed(String)
    }

    private let store: any HealthStore
    public private(set) var state: State = .idle

    public init(store: any HealthStore) {
        self.store = store
    }

    /// Import an unzipped `apple_health_export` directory, or an `export.xml`
    /// directly.
    public func run(
        from url: URL,
        onState: @escaping @Sendable (State) -> Void = { _ in }
    ) async throws -> Outcome {
        let started = Date()
        let xml = url.hasDirectoryPath ? url.appending(path: "export.xml") : url

        let importer = AppleHealthImporter()
        var parsed = 0
        var stored = 0
        var duplicates = 0
        var rejected: [String: Int] = [:]
        var lo: CalendarDay?
        var hi: CalendarDay?

        // The parse is synchronous and CPU-bound; keep it off the main actor so
        // a 293 MB file never blocks a frame.
        let batches = try await Task.detached(priority: .userInitiated) { () -> [[Sample]] in
            var collected: [[Sample]] = []
            try importer.importExport(at: xml, onProgress: { progress in
                onState(.parsing(fraction: progress.fraction, records: progress.recordsSeen))
            }, sink: { batch in
                collected.append(batch)
            })
            return collected
        }.value

        for batch in batches {
            parsed += batch.count
            let result = try await store.ingest(batch)
            stored += result.inserted
            duplicates += result.duplicates
            for (key, count) in result.rejected { rejected[key, default: 0] += count }
            if let affected = result.affected {
                lo = min(lo ?? affected.start, affected.start)
                hi = max(hi ?? affected.end, affected.end)
            }
        }

        for (key, count) in importer.issues { rejected[key, default: 0] += count }

        var affected: DayRange?
        if let lo, let hi {
            affected = DayRange(start: lo, end: hi)
            let days = Calendar.current.dateComponents(
                [.day], from: lo.date(), to: hi.date()).day ?? 0
            state = .rebuilding(days: days + 1)
            onState(state)
            // Scoped to what actually changed. A re-import that touched one new
            // day must not rebuild four years of rollups.
            try await store.rebuildRollups(for: affected!)
        }

        state = .finished
        onState(state)

        return Outcome(
            recordsParsed: parsed,
            samplesStored: stored,
            duplicates: duplicates,
            rejected: rejected,
            daysAffected: affected,
            duration: Date().timeIntervalSince(started))
    }
}
