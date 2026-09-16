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

    private let store: SQLiteHealthStore
    public private(set) var state: State = .idle

    /// Concrete rather than `any HealthStore`: the import needs the
    /// synchronous write path, which only makes sense for a real store.
    public init(store: SQLiteHealthStore) {
        self.store = store
    }

    public enum SessionError: Error, Sendable, LocalizedError {
        case noExportFound(URL)

        public var errorDescription: String? {
            switch self {
            case .noExportFound(let url):
                """
                No export.xml inside “\(url.lastPathComponent)”. On your iPhone: \
                Health → your profile picture → Export All Health Data.
                """
            }
        }
    }

    /// Resolve whatever was handed over to the `export.xml` inside it.
    ///
    /// Asks the filesystem rather than reading `hasDirectoryPath`, which is a
    /// trailing-slash heuristic: a directory URL built with `appending(path:)`
    /// reports false, and the import would then try to parse the folder itself.
    ///
    /// Looks at the top level and one level down, the latter because both the
    /// archive and the folder wrap everything in `apple_health_export/`.
    /// Deliberately not a recursive walk — descending a whole home directory
    /// looking for a file is not a file picker's job.
    public static func locateExportXML(in url: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard isDirectory.boolValue else { return url }

        let direct = url.appending(path: "export.xml")
        if FileManager.default.isReadableFile(atPath: direct.path) { return direct }

        let children = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil)) ?? []
        for child in children {
            let nested = child.appending(path: "export.xml")
            if FileManager.default.isReadableFile(atPath: nested.path) { return nested }
        }
        throw SessionError.noExportFound(url)
    }

    /// Running counts, accumulated inside the parse.
    private final class Tally: @unchecked Sendable {
        var parsed = 0
        var stored = 0
        var duplicates = 0
        var failedBatches = 0
        var rejected: [String: Int] = [:]
        var lo: CalendarDay?
        var hi: CalendarDay?
    }

    /// Import an unzipped `apple_health_export` directory, or an `export.xml`
    /// directly.
    public func run(
        from url: URL,
        onState: @escaping @Sendable (State) -> Void = { _ in }
    ) async throws -> Outcome {
        let started = Date()
        let xml = try Self.locateExportXML(in: url)

        let importer = AppleHealthImporter()
        let store = self.store

        // The store is written from INSIDE the parse, batch by batch. An
        // earlier version collected every batch into an array first, which held
        // all 664,515 samples in memory at once and defeated the entire reason
        // the importer batches at all.
        //
        // The counters are a class rather than locals because the sink is an
        // escaping closure; the parse is single-threaded, so no lock is needed.
        let tally = Tally()

        try await Task.detached(priority: .userInitiated) {
            try importer.importExport(at: xml, onProgress: { progress in
                onState(.parsing(fraction: progress.fraction, records: progress.recordsSeen))
            }, sink: { batch in
                tally.parsed += batch.count
                guard let result = try? store.ingestSynchronously(batch) else {
                    tally.failedBatches += 1
                    return
                }
                tally.stored += result.inserted
                tally.duplicates += result.duplicates
                for (key, count) in result.rejected {
                    tally.rejected[key, default: 0] += count
                }
                if let affected = result.affected {
                    tally.lo = Swift.min(tally.lo ?? affected.start, affected.start)
                    tally.hi = Swift.max(tally.hi ?? affected.end, affected.end)
                }
            })
        }.value

        let parsed = tally.parsed
        let stored = tally.stored
        let duplicates = tally.duplicates
        var rejected = tally.rejected
        let lo = tally.lo
        let hi = tally.hi
        if tally.failedBatches > 0 {
            rejected["batch_write_failed", default: 0] += tally.failedBatches
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
