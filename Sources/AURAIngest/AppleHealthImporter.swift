import Foundation
import AURACore

/// Streams an Apple Health `export.xml` into normalized samples.
///
/// `XMLParser` (SAX) rather than any tree-based API. The reference export is
/// 293 MB and 664,515 records; loading that as a DOM is a multi-gigabyte
/// allocation for no benefit, since every record is independent and read once.
///
/// `export_cda.xml` (a further 56 MB of HL7 CDA) is deliberately ignored — it
/// restates the same data in a clinical-document wrapper and adds nothing.
///
/// One thing `XMLParser` gives us for free that a hand-rolled scanner does not:
/// **entity decoding**. Apple writes `device="&lt;&lt;HKDevice: 0x...&gt;"` on
/// nearly every wearable sample, and a source name can carry an encoded
/// non-breaking space. Left encoded, `"Apple Watch"` fails its trust-order
/// match, the most trustworthy device ranks as unknown, and every deduplicated
/// total silently comes out wrong. The Python reference had exactly that bug
/// until the edge-case fixture caught it.
public final class AppleHealthImporter: NSObject {

    public struct Progress: Sendable {
        public let recordsSeen: Int
        public let bytesRead: Int64
        public let totalBytes: Int64
        public var fraction: Double {
            totalBytes > 0 ? Double(bytesRead) / Double(totalBytes) : 0
        }
    }

    public enum ImportError: Error, Sendable {
        case unreadable(URL)
        case notAnAppleHealthExport
        case unsupportedExportVersion(String)
        case parseFailed(String)
    }

    /// Counts of everything that did not become a sample, by reason.
    /// Surfaced rather than swallowed: an import that silently drops 3% of a
    /// person's data is worse than one that fails.
    public private(set) var issues: [String: Int] = [:]

    private var batchSize = 10_000
    private var pending: [Sample] = []
    private var sink: (([Sample]) -> Void)?
    private var onProgress: ((Progress) -> Void)?
    private var seen = 0
    private var totalBytes: Int64 = 0

    public override init() { super.init() }

    /// Parse `url`, handing batches to `sink` as they fill.
    ///
    /// Batched rather than returned whole so memory stays flat regardless of
    /// export size, and so the UI can show real progress on an import long
    /// enough to need one.
    ///
    /// Synchronous by design — call it off the main actor. `XMLParser` drives
    /// its own run loop and interleaving an async sink into its delegate
    /// callbacks buys nothing but reordering risk.
    public func importExport(
        at url: URL,
        batchSize: Int = 10_000,
        onProgress: ((Progress) -> Void)? = nil,
        sink: ([Sample]) -> Void
    ) throws {
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw ImportError.unreadable(url)
        }
        guard let parser = XMLParser(contentsOf: url) else {
            throw ImportError.unreadable(url)
        }

        self.batchSize = batchSize
        self.totalBytes = (try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int64) as? Int64 ?? 0
        self.issues = [:]
        self.seen = 0
        self.pending = []

        // withoutActuallyEscaping: the sink is used only for the duration of
        // parse(), which returns before this function does.
        try withoutActuallyEscaping(sink) { sink in
            self.sink = sink
            self.onProgress = onProgress
            defer { self.sink = nil; self.onProgress = nil }

            parser.delegate = self
            guard parser.parse() else {
                throw ImportError.parseFailed(
                    parser.parserError?.localizedDescription ?? "unknown")
            }
            flush()
        }

        guard seen > 0 || !issues.isEmpty else {
            throw ImportError.notAnAppleHealthExport
        }
    }

    private func flush() {
        guard !pending.isEmpty else { return }
        sink?(pending)
        pending.removeAll(keepingCapacity: true)
    }
}

// MARK: - XMLParserDelegate

extension AppleHealthImporter: XMLParserDelegate {

    public func parser(_ parser: XMLParser, didStartElement element: String,
                       namespaceURI: String?, qualifiedName: String?,
                       attributes: [String: String]) {
        guard element == "Record" else { return }

        guard let rawType = attributes["type"],
              let identifier = Self.stripPrefix(rawType)
        else { return }

        guard let metric = MetricCatalog[identifier] else {
            issues["unmapped:\(identifier)", default: 0] += 1
            return
        }

        guard let start = Self.date(attributes["startDate"]) else {
            issues["unparseable_date:\(identifier)", default: 0] += 1
            return
        }
        // endDate is optional in practice; a missing one means an instant.
        let end = Self.date(attributes["endDate"]) ?? start

        let raw = attributes["value"] ?? ""
        var value: Double?
        var category: String?

        if metric.aggregation == .count || metric.aggregation == .interval
            || raw.hasPrefix("HKCategoryValue") {
            category = raw
        } else {
            guard let parsed = Double(raw) else {
                issues["unparseable_value:\(identifier)", default: 0] += 1
                return
            }
            // An unexpected unit is a data-integrity event, not something to
            // silently coerce. A US-locale export emits `mi`, `lb` and `degF`,
            // and guessing a conversion is how a dashboard invents numbers.
            let unit = attributes["unit"] ?? ""
            guard metric.unit.accepts(unit) else {
                issues["unit_mismatch:\(identifier):got=\(unit):want=\(metric.unit.rawValue)",
                       default: 0] += 1
                return
            }
            value = parsed
        }

        pending.append(Sample(
            metric: identifier, value: value, category: category,
            source: attributes["sourceName"] ?? "unknown",
            device: attributes["device"],
            start: start, end: end))

        seen += 1

        if pending.count >= batchSize {
            flush()
            onProgress?(Progress(recordsSeen: seen,
                                 bytesRead: Int64(parser.lineNumber),
                                 totalBytes: totalBytes))
        }
    }

    // MARK: Parsing helpers

    /// `HKQuantityTypeIdentifierStepCount` -> `StepCount`.
    static func stripPrefix(_ type: String) -> String? {
        for prefix in ["HKQuantityTypeIdentifier", "HKCategoryTypeIdentifier"] {
            if type.hasPrefix(prefix) {
                return String(type.dropFirst(prefix.count))
            }
        }
        return nil
    }

    /// Apple writes `2026-09-15 08:48:04 +0530`.
    ///
    /// A single shared formatter, because creating one per record is the
    /// difference between a parse that takes seconds and one that takes
    /// minutes at 664,515 records.
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        return dateFormatter.date(from: string)
    }
}
