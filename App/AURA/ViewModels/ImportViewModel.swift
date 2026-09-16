import Foundation
import AppKit
import Observation
import AURACore
import AURAStore
import AURAIngest

/// Drives one import, from a dropped file to a finished count.
///
/// The screen's only job is to be honest about a long operation: what it is
/// doing, how far along it is, and — the part most importers get wrong — that
/// re-importing an export you have already imported is *supposed* to report
/// almost nothing new. Every export the Health app produces contains the whole
/// history, so a second import is ~99% duplicates. That is the pipeline working.
@Observable
@MainActor
public final class ImportViewModel {

    public enum Phase {
        case idle
        /// A `.zip` was handed over. AURA cannot open it itself — see
        /// `expandWithFinder` — so this phase asks for one click rather than
        /// failing at the person for dropping the file macOS gave them.
        case needsExpanding(URL)
        /// Locating `export.xml` inside whatever was dropped.
        case preparing(String)
        case parsing(fraction: Double, records: Int)
        case rebuilding(days: Int)
        case finished(ImportSession.Outcome)
        case failed(String)
    }

    public enum Failure: LocalizedError {
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

    public private(set) var phase: Phase = .idle

    public var isRunning: Bool {
        switch phase {
        case .preparing, .parsing, .rebuilding: true
        case .idle, .needsExpanding, .finished, .failed: false
        }
    }

    private let store: SQLiteHealthStore
    /// Called once an import lands data, so the rest of the app does not keep
    /// describing the database as it was before.
    private let onImported: @MainActor (DayRange?) -> Void

    public init(store: SQLiteHealthStore,
                onImported: @escaping @MainActor (DayRange?) -> Void = { _ in }) {
        self.store = store
        self.onImported = onImported
    }

    // MARK: Running

    public func start(_ url: URL) {
        guard !isRunning else { return }

        // Zips are handled by Finder, not here. Reading one would mean either a
        // third-party zip library — a dependency, and its supply chain, for an
        // app whose premise is that it is small and auditable — or shelling out
        // to `/usr/bin/ditto`, which the App Sandbox forbids. The sandbox is
        // worth more than the click it saves: this app reads four years of
        // someone's health history.
        guard url.pathExtension.lowercased() != "zip" else {
            phase = .needsExpanding(url)
            return
        }

        phase = .preparing(url.lastPathComponent)

        Task {
            // Non-sandboxed builds don't need this, sandboxed ones do, and
            // balancing the call costs nothing either way.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            do {
                let xml = try Self.locateExportXML(in: url)

                let session = ImportSession(store: store)
                let outcome = try await session.run(from: xml) { [weak self] state in
                    Task { @MainActor in self?.apply(state) }
                }

                phase = .finished(outcome)
                onImported(try? await store.availableRange())
            } catch {
                phase = .failed((error as? LocalizedError)?.errorDescription
                                ?? error.localizedDescription)
            }
        }
    }

    /// Hands the archive to Archive Utility, the same thing a double-click in
    /// Finder does. Sandbox-legal because the person chose this exact file.
    public func expandWithFinder() {
        guard case .needsExpanding(let url) = phase else { return }
        NSWorkspace.shared.open(url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        phase = .idle
    }

    public func reset() {
        guard !isRunning else { return }
        phase = .idle
    }

    private func apply(_ state: ImportSession.State) {
        // The session reports `.finished` before `run` returns; taking it here
        // would drop the outcome on the floor, so the caller sets that phase.
        switch state {
        case .parsing(let fraction, let records):
            phase = .parsing(fraction: fraction, records: records)
        case .rebuilding(let days):
            phase = .rebuilding(days: days)
        case .idle, .finished, .failed:
            break
        }
    }

    // MARK: Finding the export

    /// Accepts either the unzipped `apple_health_export` folder or the
    /// `export.xml` inside it — both are reasonable things to drop on a window.
    ///
    /// Looks at the top level and one level down, the latter because the
    /// archive wraps everything in `apple_health_export/`. Deliberately not a
    /// recursive walk: descending a whole home directory looking for a file is
    /// not a file picker's job.
    static func locateExportXML(in url: URL) throws -> URL {
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
        throw Failure.noExportFound(url)
    }
}
