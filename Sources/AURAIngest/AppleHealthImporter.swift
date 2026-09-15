import Foundation
import AURACore

/// Streams an Apple Health `export.xml` into normalized samples.
///
/// Implemented with `XMLParser` (SAX) rather than any DOM-based API. The
/// reference export is 293 MB and 664,515 records; loading that as a tree is a
/// multi-gigabyte allocation for no benefit, since every record is independent
/// and processed once.
///
/// Note on scope: `export_cda.xml` (a further 56 MB of HL7 CDA) is deliberately
/// ignored. It duplicates the same data in a clinical-document wrapper and adds
/// nothing AURA needs.
public actor AppleHealthImporter {

    public struct Progress: Sendable {
        public let recordsSeen: Int
        public let bytesRead: Int64
        public let totalBytes: Int64
        public var fraction: Double {
            totalBytes > 0 ? Double(bytesRead) / Double(totalBytes) : 0
        }
    }

    public init() {}

    /// Parse and hand batches to `sink` as they are produced.
    ///
    /// Batched rather than returned whole so memory stays flat regardless of
    /// export size, and so the UI can show real progress on an import that
    /// takes long enough to need one.
    public func importExport(
        at url: URL,
        batchSize: Int = 10_000,
        onProgress: @Sendable (Progress) -> Void = { _ in },
        sink: @Sendable ([Sample]) async throws -> Void
    ) async throws {
        // M2: XMLParser delegate -> normalize(unit/value/date) -> batch -> sink.
        throw ImportError.notImplemented
    }

    public enum ImportError: Error, Sendable {
        case notImplemented
        case unreadable(URL)
        case notAnAppleHealthExport
        /// The export's own `HealthKit Export Version`, if it ever moves past
        /// 14 in a way that breaks the record shape.
        case unsupportedExportVersion(String)
    }
}
