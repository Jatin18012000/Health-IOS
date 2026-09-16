import Foundation
import AppKit
import UniformTypeIdentifiers
import Observation
import AURACore
import AURAStore
import AURAMemory
import AURAReport

/// The three things Settings actually *does*: a report out, a backup out, a
/// backup back in. Everything else on that screen is a preference the view
/// writes directly.
@Observable
@MainActor
public final class SettingsViewModel {

    public enum Job: Equatable {
        case none
        case buildingReport
        case writingBackup
        case restoring
    }

    public struct Note: Identifiable, Equatable {
        public let id = UUID()
        public let text: String
        public let isError: Bool
    }

    public private(set) var job: Job = .none
    public private(set) var note: Note?
    /// Set once a restore is staged: nothing changes until the app is relaunched.
    public private(set) var restorePending = false

    public var reportMonths = 12
    public var passphrase = ""
    public var confirmPassphrase = ""

    private let store: SQLiteHealthStore
    private let memory: MemoryStore?
    private let preferences: Preferences

    public init(store: SQLiteHealthStore, memory: MemoryStore?, preferences: Preferences) {
        self.store = store
        self.memory = memory
        self.preferences = preferences
    }

    public var isBusy: Bool { job != .none }

    public var passphraseProblem: String? {
        if passphrase.isEmpty { return nil }
        if passphrase.count < Backup.minimumPassphrase {
            return "At least \(Backup.minimumPassphrase) characters."
        }
        if !confirmPassphrase.isEmpty, passphrase != confirmPassphrase {
            return "The two don't match."
        }
        return nil
    }

    public func dismissNote() { note = nil }

    // MARK: Report

    /// A PDF for a clinician, containing no generated prose at all.
    ///
    /// Worth restating where the button lives: `HealthReport` carries figures,
    /// counts and provenance and nothing else — no score, no interpretation, no
    /// reference ranges. `OutputGuard` polices what she says aloud, and a
    /// document she never sees would route straight around it.
    public func exportReport() async {
        guard !isBusy else { return }

        guard let day = try? await store.availableRange()?.end else {
            note = Note(text: "There's no health data to report on yet.", isError: true)
            return
        }

        job = .buildingReport
        defer { job = .none }

        do {
            let report = try await HealthReport.build(
                store: store, memory: memory, endingOn: day, months: reportMonths)

            // The panel comes after the build, not before: a save panel that
            // appears and then fails is worse than a pause.
            guard let url = Self.savePanel(
                name: "AURA health summary \(day).pdf",
                type: .pdf,
                message: "The report contains measurements and their provenance — no interpretation.")
            else { return }

            try ReportExporter.writePDF(report, to: url)
            note = Note(text: "Saved \(report.rows.count) metrics over \(report.totalDays) days to \(url.lastPathComponent).",
                        isError: false)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            note = Note(text: describe(error), isError: true)
        }
    }

    // MARK: Backup

    public func writeBackup() async {
        guard !isBusy, passphraseProblem == nil,
              passphrase.count >= Backup.minimumPassphrase,
              passphrase == confirmPassphrase else { return }

        guard let url = Self.savePanel(
            name: "AURA \(CalendarDay(Date())).aurabackup",
            type: Self.backupType,
            message: "Encrypted with your passphrase. There is no recovery if you lose it.")
        else { return }

        job = .writingBackup
        defer { job = .none }

        var stores = ["aura.sqlite": AppContainer.storeURL]
        if memory != nil { stores["memory.sqlite"] = AppContainer.memoryURL }

        let phrase = passphrase
        do {
            // Off the main actor: VACUUM INTO on a 34 MB database plus AES over
            // the result is not a frame's worth of work.
            try await Task.detached(priority: .userInitiated) {
                try Backup.write(stores: stores, to: url, passphrase: phrase)
            }.value

            preferences.recordBackup()
            passphrase = ""
            confirmPassphrase = ""
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            note = Note(text: "Wrote \(Self.bytes(size)) to \(url.lastPathComponent). Keep the passphrase somewhere you won't lose it.",
                        isError: false)
        } catch {
            note = Note(text: describe(error), isError: true)
        }
    }

    /// Restores into a staging folder, not over the live databases.
    ///
    /// Both stores are open with WAL journaling right now. Writing over
    /// `aura.sqlite` underneath an open connection corrupts it — and does so
    /// quietly, which is the worst kind. So the restored files are staged and
    /// `AppContainer` moves them into place on the next launch, before anything
    /// opens a database.
    public func restore() async {
        guard !isBusy, !passphrase.isEmpty else { return }

        guard let url = Self.openPanel(
            type: Self.backupType,
            message: "Everything AURA currently holds will be replaced when you relaunch.")
        else { return }

        job = .restoring
        defer { job = .none }

        let staging = AppContainer.stagingURL
        let phrase = passphrase
        do {
            try? FileManager.default.removeItem(at: staging)
            let manifest = try await Task.detached(priority: .userInitiated) {
                try Backup.restore(from: url, into: staging, passphrase: phrase)
            }.value

            restorePending = true
            passphrase = ""
            confirmPassphrase = ""
            note = Note(
                text: "Restored \(manifest.files.joined(separator: " and ")) from \(manifest.createdAt.formatted(date: .abbreviated, time: .shortened)). Quit and reopen AURA to use it.",
                isError: false)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            note = Note(text: describe(error), isError: true)
        }
    }

    public func cancelRestore() {
        try? FileManager.default.removeItem(at: AppContainer.stagingURL)
        restorePending = false
        note = Note(text: "Restore cancelled. Nothing was changed.", isError: false)
    }

    // MARK: What's on disk

    /// Reported rather than estimated. "Local-only" is the app's central claim,
    /// and the honest form of it is being able to point at the files.
    public struct Storage: Equatable {
        public var health = 0
        public var memory = 0
        public var total: Int { health + memory }
    }

    public func storageOnDisk() -> Storage {
        var storage = Storage()
        // WAL and shm count: they are part of the database, and a figure that
        // omits them under-reports right after a large import.
        for suffix in ["", "-wal", "-shm"] {
            storage.health += Self.size(of: AppContainer.storeURL.appendingSuffix(suffix))
            storage.memory += Self.size(of: AppContainer.memoryURL.appendingSuffix(suffix))
        }
        return storage
    }

    public static func bytes(_ count: Int) -> String {
        count.formatted(.byteCount(style: .file))
    }

    private static func size(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    // MARK: Panels

    private func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private static func savePanel(name: String, type: UTType, message: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [type]
        panel.message = message
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func openPanel(type: UTType, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [type]
        panel.message = message
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// The backup is AURA's own format, so there is no system type for it.
    /// A dynamic type off the extension is enough to filter the panel.
    static let backupType = UTType(filenameExtension: "aurabackup") ?? .data
}

extension URL {
    /// `aura.sqlite` + `-wal` -> `aura.sqlite-wal`. Not a path component and
    /// not a path extension: SQLite's sidecars are a literal suffix on the
    /// filename.
    func appendingSuffix(_ suffix: String) -> URL {
        suffix.isEmpty ? self
                       : deletingLastPathComponent()
                            .appending(path: lastPathComponent + suffix)
    }
}
