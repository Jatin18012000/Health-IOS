import Testing
import Foundation
@testable import AURACore

@Suite("Metric catalog")
struct MetricCatalogTests {

    @Test("every metric has a unique identifier")
    func uniqueIdentifiers() {
        let ids = MetricCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("only cumulative metrics use sum aggregation")
    func cumulativeImpliesSum() {
        // A summed metric that isn't marked cumulative would skip source
        // deduplication and silently double-count. This is the invariant that
        // stops that from ever being reintroduced by a one-line catalog edit.
        for metric in MetricCatalog.all where metric.aggregation == .sum {
            #expect(metric.isCumulative, "\(metric.id) sums but is not marked cumulative")
        }
    }

    @Test("Cal is accepted as kilocalories but calories are not invented")
    func energyUnitAliasing() {
        #expect(Unit.kilocalories.accepts("Cal"))
        #expect(Unit.kilocalories.accepts("kcal"))
        #expect(!Unit.kilocalories.accepts("J"))
    }

    @Test("count/min resolves differently for heart rate and respiratory rate")
    func perMetricUnitAliasing() {
        // A single global alias table maps one of these wrong.
        #expect(Unit.beatsPerMinute.accepts("count/min"))
        #expect(Unit.breathsPerMinute.accepts("count/min"))
        #expect(MetricCatalog["HeartRate"]?.unit == .beatsPerMinute)
        #expect(MetricCatalog["RespiratoryRate"]?.unit == .breathsPerMinute)
    }
}

@Suite("Source deduplication")
struct SourceResolverTests {

    private func sample(_ source: String, _ value: Double,
                        _ startMin: Int, _ endMin: Int) -> Sample {
        let base = Date(timeIntervalSince1970: 1_757_721_600)
        return Sample(metric: "StepCount", value: value, source: source,
                      start: base.addingTimeInterval(Double(startMin) * 60),
                      end: base.addingTimeInterval(Double(endMin) * 60))
    }

    @Test("a single source is summed untouched")
    func singleSource() {
        let total = SourceResolver.default.total(of: [
            sample("iPhone (2)", 100, 0, 60),
            sample("iPhone (2)", 200, 60, 120),
        ])
        #expect(total == 300)
    }

    @Test("fully overlapping sources do not double count")
    func fullOverlap() {
        // Watch outranks iPhone, so the iPhone's identical hour contributes
        // nothing rather than doubling the total.
        let total = SourceResolver.default.total(of: [
            sample("Jatin\u{00a0}s Apple\u{00a0}Watch", 500, 0, 60),
            sample("iPhone (2)", 400, 0, 60),
        ])
        #expect(total == 500)
    }

    @Test("partial overlap contributes pro rata")
    func partialOverlap() {
        // Watch claims 0-60. The iPhone's 30-90 sample is half uncovered,
        // so half its value counts.
        let total = SourceResolver.default.total(of: [
            sample("Jatin\u{00a0}s Apple\u{00a0}Watch", 500, 0, 60),
            sample("iPhone (2)", 400, 30, 90),
        ])
        #expect(total == 700)
    }

    @Test("a non-breaking space in the source name still matches")
    func nonBreakingSpace() {
        // Apple writes "Apple\u{00a0}Watch". Matching a plain space fails
        // silently, which would demote the most trustworthy source to last.
        let resolver = SourceResolver.default
        #expect(resolver.rank(of: "Jatin\u{00a0}s Apple\u{00a0}Watch")
                < resolver.rank(of: "iPhone (2)"))
    }

    @Test("an unknown source sorts last rather than being dropped")
    func unknownSource() {
        let resolver = SourceResolver.default
        // 99, not some arbitrarily large sentinel: this exact value is what
        // `tools/reference_pipeline.py` writes and what `expected.json`
        // asserts, and it is what ends up in the `sources.priority` column —
        // see `SourceResolver.unknownRank`.
        #expect(resolver.rank(of: "SomeNewBand") == SourceResolver.unknownRank)
        let total = resolver.total(of: [sample("SomeNewBand", 250, 0, 60)])
        #expect(total == 250)
    }
}
