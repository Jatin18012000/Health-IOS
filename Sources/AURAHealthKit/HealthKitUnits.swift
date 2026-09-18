import Foundation
import AURACore

#if canImport(HealthKit)
import HealthKit

/// Canonical unit -> the `HKUnit` to read that quantity in.
///
/// ## Why this table exists and why it is the dangerous part
///
/// The XML importer reads whatever unit Apple wrote and *validates* it, because
/// it has no choice in the matter. HealthKit is the other way round: you ask
/// for a value in a unit of your choosing and it converts. That removes the
/// aliasing ambiguity — `count/min` cannot mean two things here, because the
/// metric tells us which canonical unit it wants — and replaces it with a worse
/// failure mode. A wrong row below is a silent scaling error with no exception
/// and no rejected record, and it corrupts figures that sit beside four years
/// of correctly-scaled XML data.
///
/// So the rule is explicit: **read in the `HKUnit` that matches the catalog's
/// canonical unit**, never in "whatever HealthKit's default is". Those coincide
/// for energy and diverge for distance — HealthKit's canonical length is the
/// metre, the catalog's is the kilometre, and reading the default would be a
/// 1000x error on every distance sample.
enum HealthKitUnits {

    static func hkUnit(for unit: Unit) -> HKUnit? {
        switch unit {
        case .count:            .count()
        case .kilometres:       .meterUnit(with: .kilo)
        case .metres:           .meter()
        case .centimetres:      .meterUnit(with: .centi)
        case .kilograms:        .gramUnit(with: .kilo)
        // `Cal` in an Apple export is a *kilo*calorie. Reading it as a calorie
        // is the same silent 1000x error in the other direction.
        case .kilocalories:     .kilocalorie()
        case .minutes:          .minute()
        case .milliseconds:     .secondUnit(with: .milli)
        // Both of these are `count/min` to HealthKit. They stay distinct here
        // because the metric, not the unit string, decides which one applies —
        // which is exactly the bug the XML path had to be taught to avoid.
        case .beatsPerMinute:   HKUnit.count().unitDivided(by: .minute())
        case .breathsPerMinute: HKUnit.count().unitDivided(by: .minute())
        case .percent:          .percent()
        case .celsius:          .degreeCelsius()
        case .mmHg:             .millimeterOfMercury()
        case .decibelsASPL:     .decibelAWeightedSoundPressureLevel()
        case .kmPerHour:        HKUnit.meterUnit(with: .kilo).unitDivided(by: .hour())
        case .metresPerSecond:  HKUnit.meter().unitDivided(by: .second())
        case .vo2:
            HKUnit.literUnit(with: .milli)
                .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
        case .met:
            HKUnit.kilocalorie()
                .unitDivided(by: HKUnit.hour().unitMultiplied(by: .gramUnit(with: .kilo)))
        default: nil
        }
    }

    /// `HKUnit.percent()` is a **fraction**: blood oxygen comes back as 0.97,
    /// not 97.
    ///
    /// This is stored as-is rather than multiplied up, on the reasoning that
    /// Apple's own XML exporter writes canonical HealthKit values, so
    /// `unit="%" value="0.97"` is what the existing four years in the store
    /// already hold and the two paths agree by construction.
    ///
    /// **That reasoning is not verified.** The reference export contained six
    /// `OxygenSaturation` records in four years, the edge-case fixture has
    /// none, and `tools/reference_pipeline.py` does not special-case percent —
    /// so nothing in this repository pins the scale. If the first real sync
    /// puts blood oxygen at 0.97 beside XML rows reading 97, this line is why.
    /// Recorded in `docs/DECISIONS_PENDING.md` §11.
    static let percentIsAFraction = true

    /// Every quantity type the catalog knows and HealthKit can supply.
    ///
    /// Built from `MetricCatalog` rather than listed again: a metric added
    /// there becomes readable here with no second edit, and cannot be added in
    /// one place and forgotten in the other.
    static func quantityTypes() -> [HKQuantityType: Metric] {
        var types: [HKQuantityType: Metric] = [:]
        for metric in MetricCatalog.all where metric.aggregation != .interval {
            let identifier = HKQuantityTypeIdentifier(
                rawValue: "HKQuantityTypeIdentifier" + metric.id)
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier),
                  hkUnit(for: metric.unit) != nil
            else { continue }
            types[type] = metric
        }
        return types
    }

    /// Category types, which carry a value that is an enum rather than a number.
    static func categoryTypes() -> [HKCategoryType: Metric] {
        var types: [HKCategoryType: Metric] = [:]
        for metric in MetricCatalog.all {
            let identifier = HKCategoryTypeIdentifier(
                rawValue: "HKCategoryTypeIdentifier" + metric.id)
            guard let type = HKCategoryType.categoryType(forIdentifier: identifier)
            else { continue }
            types[type] = metric
        }
        return types
    }

    /// The `HKCategoryValueSleepAnalysis` spellings Apple's XML export writes.
    ///
    /// The sleep pipeline keys on these exact strings — `SleepNight`
    /// reconstruction reads them to separate staged nights from in-bed-only
    /// ones, and `CLAUDE.md` makes that separation an invariant. HealthKit
    /// hands over an integer instead, so this table is what keeps a synced
    /// night and an imported night the same kind of thing.
    ///
    /// Anything unrecognised returns nil and the sample is dropped rather than
    /// guessed at: a mislabelled sleep stage silently changes which nights
    /// count as staged, and percentiles then rank a night against the wrong
    /// population.
    static func sleepCategory(_ value: Int) -> String? {
        guard let stage = HKCategoryValueSleepAnalysis(rawValue: value) else { return nil }
        return switch stage {
        case .inBed:             "HKCategoryValueSleepAnalysisInBed"
        case .asleepCore:        "HKCategoryValueSleepAnalysisAsleepCore"
        case .asleepDeep:        "HKCategoryValueSleepAnalysisAsleepDeep"
        case .asleepREM:         "HKCategoryValueSleepAnalysisAsleepREM"
        case .asleepUnspecified: "HKCategoryValueSleepAnalysisAsleepUnspecified"
        case .awake:             "HKCategoryValueSleepAnalysisAwake"
        @unknown default:        nil
        }
    }
}
#endif
