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
                // Resolved here as well as inside `run`, so a folder with no
                // export.xml fails before the progress UI appears rather than
                // one frame into it.
                let xml = try ImportSession.locateExportXML(in: url)

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
}
